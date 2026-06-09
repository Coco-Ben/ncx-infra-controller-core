curl -X GET "https://api.ngc.nvidia.com/v2/org/{provider-org-name}/nico/infrastructure-provider/current" \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}"