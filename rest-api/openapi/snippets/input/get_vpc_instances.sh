curl -X GET "https://api.ngc.nvidia.com/v2/org/{tenant-org-name}/nico/instance?siteId=bd4692bd-da95-410e-911a-d492fe2d35f8&vpcId=f466a2d5-5820-4824-a845-3218fdff801b" \
-H "Content-Type: application/json" -H "Accept: application/json" \
-H "Authorization: Bearer ${TOKEN}"
