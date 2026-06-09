curl -X GET "https://api.ngc.nvidia.com/v2/org/{org}/nico/network-security-group" \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -H "Authorization: Bearer ${TOKEN}"
