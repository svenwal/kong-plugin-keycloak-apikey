local typedefs = require "kong.db.schema.typedefs"

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local schema = {
  name = plugin_name,
  fields = {
    { consumer = typedefs.no_consumer },  -- this plugin cannot be configured on a consumer (typical for auth plugins)
    { protocols = typedefs.protocols_http },
    { config = {
        -- The 'config' record is the custom part of the plugin schema
        type = "record",
        fields = {
          { key_header_name = {
              type = "string",
              default = "apikey",
              required = true
              }},
         { return_unautorized_if_apikey_is_missing = {
                type = "boolean",
                default = true,
                required = true
                }},
          { keycloak_base_url = {
              type = "string",
              required = true
              }},
          { keycloak_realm = {
              type = "string",
              required = true
              }},
          { keycloak_client_id = {
              type = "string",
              required = true,
              referenceable = true,
              }},
          { keycloak_client_secret = {
              type = "string",
              required = true,
              referenceable = true,
              }},
          { keycloak_admin_username = {
              type = "string",
              required = true,
              referenceable = true,
              }},
          { keycloak_admin_password = {
              type = "string",
              required = true,
              referenceable = true,
              }},
          { keycloak_admin_realm = {
              type = "string",
              default = "master",
              required = true,
           }},
        },
        entity_checks = {
        },
      },
    },
  },
}

return schema
