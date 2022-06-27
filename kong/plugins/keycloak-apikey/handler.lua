local plugin = {
    PRIORITY = 1000, -- set the plugin priority, which determines plugin execution order
    VERSION = "0.1",
  }

  function get_admin_token(id, secret) 
    return "sddfkjkaak"
  end
  
  function plugin:access(plugin_conf)
    local admin_api_url = keycloak_base_url .. '/auth/admin/' .. keycloak_realm
    local token = get_admin_token(keycloak_id, keycloak_secret)
 
     
  
  end 
  
  
  return plugin
