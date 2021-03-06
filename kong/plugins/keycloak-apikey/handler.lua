local plugin = {
    PRIORITY = 1010, -- set the plugin priority, which determines plugin execution order
    VERSION = "0.9",
  }
  
  function plugin:access(plugin_conf)
    -- >>>>>> checking if we got an apikey at all
    local apikey = kong.request.get_header(plugin_conf.key_header_name)
    if apikey == nil then
      kong.log.info("No token found in header " .. plugin_conf.key_header_name)
      if plugin_conf.return_unautorized_if_apikey_is_missing then
        kong.response.exit(401, 'Authentication required')
      else
        kong.log.info("Parameter return_unautorized_if_apikey_is_missing is set to true so we will not deny the request")
        return
      end
    end

    -- >>>>>> checking if client token is cached - if not execute validate_apikey to fetch it
    local str = require "resty.string"
    local token_cache_key = "keycloakapikey_" .. str.to_hex(plugin_conf.keycloak_base_url .. "_" .. plugin_conf.keycloak_admin_realm .. "_" .. apikey)
    local opts = { ttl = plugin_conf.token_ttl }
    local token, err = kong.cache:get(token_cache_key, opts, validate_apikey, plugin_conf, apikey)
    if err then
      kong.log.err(err)
    end

    kong.service.request.add_header("Authorization", "Bearer " .. token)

  end



  -- ******** Apikey code checking starts here
  function validate_apikey(plugin_conf, apikey)
    -- >> Generating admin token if not already cached
    local str = require "resty.string"
    kong.log.debug("Loading the admin token")
    local admin_cache_key = "keycloakapikeyadmin_" .. str.to_hex(plugin_conf.keycloak_client_id .. "_" .. plugin_conf.keycloak_admin_username .. "_" .. plugin_conf.keycloak_base_url .. "_" .. plugin_conf.keycloak_admin_realm)
    local opts = { ttl = plugin_conf.keycloak_admin_token_ttl }
    local admin_token, err = kong.cache:get(admin_cache_key, opts, get_admin_token, plugin_conf)
    if err then
      kong.log.err(err)
    end

    local http = require "resty.http"
    local httpc = http.new()
    local admin_api_url = plugin_conf.keycloak_base_url .. '/auth/admin/realms/' .. plugin_conf.keycloak_realm
  
    -- >>>>>> looking up the client id in Keycloak and retrieving the Keycloak internal ID for it

    local res, err = httpc:request_uri(admin_api_url .. "/clients/", {
      method = "GET",
      headers = {
        ["Authorization"] = "Bearer " .. admin_token,
      },
      query = {
        clientId = apikey
      },
      keepalive_timeout = 60,
      keepalive_pool = 10
    })
    if not res then
      kong.log.info("Not able to get a response from the clients endpoint")
      return kong.response.exit(403, 'Invalid credentials')
    end 
    if not res.status == 200 then
      kong.log.info("Client not found - apikey not valid")
      return kong.response.exit(403, 'Invalid credentials')
    end
   
    local cjson = require("cjson.safe").new()
    local serialized_content_id, err = cjson.decode(res.body)
    if not serialized_content_id then
      kong.log.debug("Clients endpoint has not returned parsable JSON") 
      return kong.response.exit(401, 'Invalid credentials')
    end

    if not serialized_content_id[1] then
      kong.log.debug("We have not gotten a Keycloak Id for the client_id (no first entry in array)")         
      return kong.response.exit(401, 'Invalid credentials') 
    end

    local keycloak_id = serialized_content_id[1].id

    if not keycloak_id then
      kong.log.debug("We have not gotten a Keycloak Id for the client_id (no id parameter in JSON)") 
      return kong.response.exit(401, 'Invalid credentials')
    end

    -- >>>>>> getting the client secret
    local res, err = httpc:request_uri(admin_api_url .. "/clients/" .. keycloak_id .. "/client-secret", {
      method = "GET",
      headers = {
        ["Authorization"] = "Bearer " .. admin_token,
      },
      keepalive_timeout = 60,
      keepalive_pool = 10
    })
    if not res then
      kong.log.debug("Cannot get the client secret - no response from /client-secret endpoint")
      return kong.response.exit(403, 'Invalid credentials')
    end 
  

    local serialized_content, err = cjson.decode(res.body)
    if not serialized_content then
      kong.log.debug("Returned content from /client-secret is no parsable JSON")
      return kong.response.exit(403, 'Invalid credentials')
    end
    if not serialized_content.value then
      kong.log.debug("Did not receive a secret from /client-secret")
      return kong.response.exit(403, 'Invalid credentials')
    end
    local client_secret = serialized_content.value


    -- >>>>>>> Getting the JWT for this client

    local res, err = httpc:request_uri(plugin_conf.keycloak_base_url .. "/auth/realms/" .. plugin_conf.keycloak_realm .. "/protocol/openid-connect/token", {
      method = "POST",
      body = "grant_type=client_credentials&client_id=" .. apikey .. "&client_secret=" .. client_secret,
       headers = {
         ["Content-Type"] = "application/x-www-form-urlencoded",
       },
     })
    if not res then
      kong.log.debug("Unable to access token endpoint")
      return kong.response.exit(401, 'Invalid credentials')
    end 

    local client_token, err = cjson.decode(res.body)
    if not client_token then
      kong.log.debug("Token endpoint has not returned parsable JSON") 
      return kong.response.exit(401, 'Invalid credentials')
    end

    if not client_token.access_token then
      kong.log.debug("Token endpoint has not returned an access token in response") 
      return kong.response.exit(401, 'Invalid credentials')
    end
    kong.log.debug("We got a valid apikey and have exchanged it to a token")
    return client_token.access_token
  end 





  -- ******* Fetching an admin token so we can get the clients secret later on


  function get_admin_token(plugin_conf) 

    local http = require "resty.http"
    local httpc = http.new()
    local res, err = httpc:request_uri(plugin_conf.keycloak_base_url .. "/auth/realms/" .. plugin_conf.keycloak_admin_realm .. "/protocol/openid-connect/token", {
       method = "POST",
      body = "grant_type=password&client_id=" .. plugin_conf.keycloak_client_id .. "&client_secret=" .. plugin_conf.keycloak_client_secret .. "&username=" .. plugin_conf.keycloak_admin_username .. "&password=" .. plugin_conf.keycloak_admin_password,
       headers = {
         ["Content-Type"] = "application/x-www-form-urlencoded",
       },
     })

    if not res then
      kong.log.warn("Not able to access token endpoint for admin token creation")
      kong.log.warn("Tried url " .. plugin_conf.keycloak_base_url .. "/auth/realms/" .. plugin_conf.keycloak_admin_realm .. "/protocol/openid-connect/token")
      kong.log.warn("Tried POST body: grant_type=password&client_id=" .. plugin_conf.keycloak_client_id .. "&client_secret=xxxx&username=" .. plugin_conf.keycloak_admin_username .. "&password=xxx") 
      kong.log.warn(err)
      return kong.response.exit(403, 'Invalid credentials')
    end 
    local cjson = require("cjson.safe").new()

    local serialized_content, err = cjson.decode(res.body)
    if not serialized_content then
      kong.log.warn("Admin token creation failed due to non-parsable response from token endpoint")
      return kong.response.exit(403, 'Invalid credentials')
    end
    if not serialized_content.access_token then
      kong.log.warn("Admin token creation failed due to no token embedded in response")
      return kong.response.exit(403, 'Invalid credentials')
    end
    return serialized_content.access_token
  end
  
  return plugin
