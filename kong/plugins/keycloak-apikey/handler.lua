local plugin = {
    PRIORITY = 1010, -- set the plugin priority, which determines plugin execution order
    VERSION = "0.4",
  }


  -- ******* Fetching an admin token so we can get the clients secret later on
  -- TODO:
  --  - caching
  --  - other flow than password flow!?
  --  - so far using the master realm based on my personal Keycloak setup. Would be better to use the same realm as the client

  function get_admin_token(keycloak_base_url, keycloak_realm, client_id, client_secret, admin_username, admin_password) 
    local http = require "resty.http"
    local httpc = http.new()
    local res, err = httpc:request_uri(keycloak_base_url .. "/auth/realms/" .. keycloak_realm .. "/protocol/openid-connect/token", {
       method = "POST",
      body = "grant_type=password&client_id=" .. client_id .. "&client_secret=" .. client_secret .. "&username=" .. admin_username .. "&password=" .. admin_password,
       headers = {
         ["Content-Type"] = "application/x-www-form-urlencoded",
       },
     })

    if not res then
      kong.log.warn("Not able to access token endpoint for admin token creation")
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


  -- ******** Actual plugin code starts here
  
  function plugin:access(plugin_conf)
    -- >>>>>> checking if we got an apikey at all
    local apikey = kong.request.get_header(plugin_conf.key_header_name)
    if apikey == nil then
      kong.log.info("No token found in header " .. plugin_conf.key_header_name)
      kong.response.exit(401, 'Authentication required')
    end

    local admin_api_url = plugin_conf.keycloak_base_url .. '/auth/admin/realms/' .. plugin_conf.keycloak_realm
    kong.log.debug("Fetching an admin token")
    local token = get_admin_token(plugin_conf.keycloak_base_url, plugin_conf.keycloak_admin_realm, plugin_conf.keycloak_client_id, plugin_conf.keycloak_client_secret, plugin_conf.keycloak_admin_username, plugin_conf.keycloak_admin_password)

    local http = require "resty.http"
    local httpc = http.new()


    -- >>>>>> looking up the client id in Keycloak and retrieving the Keycloak internal ID for it

    local res, err = httpc:request_uri(admin_api_url .. "/clients/", {
      method = "GET",
      headers = {
        ["Authorization"] = "Bearer " .. token,
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

    kong.log.debug(res.body)

    local keycloak_id = serialized_content_id[1].id
    if not keycloak_id then
      kong.log.debug("Token endpoint has not returned an access token in response") 
      return kong.response.exit(401, 'Invalid credentials')
    end

    -- >>>>>> getting the client secret
    local res, err = httpc:request_uri(admin_api_url .. "/clients/" .. keycloak_id .. "/client-secret", {
      method = "GET",
      headers = {
        ["Authorization"] = "Bearer " .. token,
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
    kong.service.request.add_header("Authorization", "Bearer " .. client_token.access_token)
  end 
  
  return plugin
