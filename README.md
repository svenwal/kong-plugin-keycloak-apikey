# Kong plugin validation an apikey against client_id in Keycloak

!!! Work in progress

## About

A Kong 🦍 plugin fetching an apikey and exchanging it to a JWT if a client with this ID exists in Keycloak.

The use case is about having a centralied storage for all users and application in Keycloak. Even so Keycloak itself does not know about apikeys we can use client_ids instead. So plugin executes an admin api call (admin credentials needed!) to the Keycloak API validating a client_id exists in the given realm. If it gets a response it fetches the client secret to create a JWT for this client which afterwards can be validating (for example roles, groups, scopes using the standard Kong OpenID Connect plugin

## Configuration parameters
|FORM PARAMETER|DEFAULT|DESCRIPTION|
|:----|:------|:------|
|config.key_header_name|apikey|The header where the apikey will be sent|
|config.keycloak_base_url||Base URL of Keycloak like https://my.keycloak.example.com. NOTE: If using a SSL endpoint make sure the certificate is trusted in the Kong setting `lua_ssl_trusted_certificate`|
|config.keycloak_realm||The realm the plugin should use to look up the client|
|config.keycloak_client_id||The client being used to create an admin token (!sensitive data)|
|config.keycloak_client_secret||The secret of the client being used to create an admin token (!sensitive data)|
|config.keycloak_admin_username||The admin username to create the admin token (!sensitive data)|
|config.keycloak_admin_password||The admin username to create the admin token (!sensitive data)|

## Known limitations / TBD

* sensitive information on the admin account for token creation needs to be securely stored in a vault: https://docs.konghq.com/gateway/latest/pdk/kong.vault/
* we need to add caching
* so far the admin token creation is fixed to the master realm - need to validate on real world Keycloak setups
