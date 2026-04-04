# Rack-Level Administration

The Rack Level Administration (RLA) component allows site administrators to manage bare metal for NVIDIA Multi-Node NVLink (MNNVL) systems such as GB200, providing the necessary rack-level topology, operations, and automation needed for resource provision and management logic in NICo. 

RLA provides a common component grouping schema with topology and location for the Chassis (physical rack) and NVL Domain (logical rack). It manages the following components on GBx00 racks:

- Compute tray
- Switch tray
- Powershelf
- Building management system provided sensors and controls

RLA provides APIs and automated workflows to manage these components for the following core tasks:

- Inventory management with topology and location
- Firmware management with NVL domain firmware consistency
- Power management with dependency and sequencing

## Rack-Level Operations

### 1. Ingestion

RLA expects a factory inventory file or a site manifest file that contains information about the equipment to be managed by NICo. In some cases, the information may be available from a service. 

The inventory/manifest file should contain the following information:

* **NVL Domain Information** 
  * ID/Name  
  * Racks in the NVL domain  
* **Rack Information**
  * ID/Name  
  * Manufacturer  
  * Serial Number  
  * Location  
* **Component Information** 
  * ID/Name  
  * Type  
  * Model  
  * Manufacturer  
  * Serial Number  
  * BMC information which includes MAC address and access credential  
  * In-rack information which includes the rack ID/Name, slot ID and tray index.  
  * Description  
  * SKU

The following describes the workflow to ingest a rack:

1. RLA retrieves the equipment information from the inventory/manifest file.  
2. The site administrator calls the RLA API to start the rack ingestion workflow.  
3. The RLA worker verifies that the expected rack information is complete and starts the ingestion process for all the components: Compute trays, switch trays, and power shelves.
4. Once all the components are ready, the rack is marked as ***ingested***. When all racks in a NVL domain have been ingested, the NVL domain is marked as ingested.

### 2. Power Control

The RLA intitiates the following power control workflows and handles the power control operations for the components.

**After Power On Validations**

1. Verify the rack inventory, such as the serial numbers for all components, BMCs, etc.  
2. Check the firmware versions.

**Power On Sequence**

1. Power on the power shelves  
2. Ping BMCs for all other components and wait until they are online.  
3. \[***Configurable***\] Perform leakage detections on all components in the rack which are liquid cooled. If any leakage is detected, pause (or cancel) the power on operation.  
4. ~~Power on the top-of-rack-switches~~  
5. Power on the switch trays  
6. Power on the compute trays  
7. Perform the after power on validations and generate a final report.

**Power Off Sequence**

1. Power off the compute trays  
2. Power off the switch trays  
3. Power off the top-of-rack-switches  
4. Power off the power shelves  
5. Perform the after power off validations and generate a final report.

**Reset Sequence**

1. Halt all the compute nodes  
2. Halt all the NVLink switches  
3. Power off all the power shelves and wait at least three minutes for the PSU capacitors to discharge  
4. Perform the power on by following the above power-on sequence.

### 3. Firmware Management and Upgrade

The firmware of all components in a nNVL is managed as a unified entity and the upgrade operations are orchestrated to be performed in a controlled manner. To achieve this goal, RLA has the following capabilities:

* Each component type has versioned firmware bundles which contain all the necessary firmware packages, such as `[compute tray, version 1.1.0] -> [[BMC, 25.06.2_NV_WW_01], [HMC, GB200Nvl-25.06-2], …]`.  
* Rack firmware versions are mapped to a list of versioned firmware bundles for each type of component within the rack, such as `[rack type, 1.0.0] -> [[compute tray, 1.1.0], [switch tray, 1.2.1], …]`.
* Since the racks from different vendors have different components requiring various firmware packages, the site administrators should be able to specify the rack types and the bundling for each rack firmware version and provide the information to access the firmware packages.  
* RLA maintains a local repository to cache the necessary firmware packages.  
* RLA instructs each component service to perform firmware upgrades on the specified components with a specified firmware bundle.

When a NVL domain FW update completes successfully, all compute trays in the NVL domain will have the same firmware version, all switch trays in the NVL domain will have the same firmware version, and the compute tray firmware and switch tray firmware are compatible with each other (as guaranteed by the NVL domain firmware bundling). If any component firmware updates in the domain cannot proceed, the whole domain firmware update will be rolled back and all components will revert back to their original installed firmware versions.

There are two scenarios for firmware upgrade via RLA:

* A planned firmware upgrade
* A detected component firmware mismatch

#### Planned Firmware Upgrade

This is scheduled and executed as part of regular maintenance or improvements.

#### Detected Component Firmware Mismatch

RLA has a scheduled periodic job to monitor the status of all components within a rack. The status includes component health and firmware version. It will detect components with mismatched firmware versions (e.g., after a component is replaced).

The recommended order for rack firmware upgrade is `[Power shelves -> Switch trays -> Compute trays]`

To minimize the impact on jobs running on the compute trays, the firmware upgrade should ideally be done when no jobs are running and no new jobs are scheduled during the upgrade. This aspect is out of scope of RLA and should be managed by other services with insights into job scheduling. RLA provides APIs for the site administrators or other services to schedule firmware upgrade tasks, which will be executed during a planned maintenance window.

#### Detected Component Firmware Mismatch

RLA has a scheduled periodic job to monitor the status of all components within a rack. The status includes component health and firmware version. It will detect components with mismatched firmware versions (e.g., after a component is replaced).

1. If the component services support firmware upgrade to a specified version, RLA initiates the firmware upgrade on the firmware mismatched components, using logic based on the types of mismatched components.  
2. If not, the newly replaced components are marked as “unavailable” for the tenant. The periodic monitoring job checks if the components are in “maintenance” mode:  
   a. If they have the expected firmware version, RLA instructs the corresponding component service to move the components out of maintenance mode.
   b. If not, RLA alerts the site administrators to plan a maintenance window for firmware upgrade. 

## REST API

### Rack Endpoints

- [GET /v2/org/{org}/carbide/rack](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Rack/operation/get-all-rack): Get all racks for the specified site.
- [GET /v2/org/{org}/carbide/rack/{rack_id}](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Rack/operation/get-rack): Retrieve a rack with the specified ID.
- [GET /v2/org/{org}/carbide/rack/validation](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Rack/operation/validate-racks): Validate rack components of all racks in the specified site by comparing the expected state to the observed state.
- [GET /v2/org/{org}/carbide/rack/{rack_id}/validation](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Rack/operation/validate-rack): Validate rack components of the specified rack by comparing the expected state to the observed state.
- [PATCH /v2/org/{org}/carbide/rack/power](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Rack/operation/power-control-racks): Control power of all racks using the optional name filter. If no filter is specified, all racks in the site are updated. Supported power states are `on`, `off`, `cycle`, `forceoff`, `forcecycle`. 
- [PATCH /v2/org/{org}/carbide/rack/{id}/power](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Rack/operation/firmware-update-rack): Control power of the specified rack. Supported power states are `on`, `off`, `cycle`, `forceoff`, `forcecycle`.
- [PATCH /v2/org/{org}/carbide/rack/firmware](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Rack/operation/firmware-update-racks): Update firmware on racks using rhe optional name filter. If no filter is specified, all racks in the site are updated.
- [PATCH /v2/org/{org}/carbide/rack/{id}/firmware](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Rack/operation/firmware-update-rack): Update the firmware on the specified rack.
- [POST /v2/org/{org}/carbide/rack/bringup](hhttps://nvidia.github.io/ncx-infra-controller-rest/#tag/Rack/operation/bringup-racks): Bring up racks using the optional name filter. If no filter is specified, targets all racks in the Site.
- [GET /v2/org/{org}/carbide/rack/task/{id}](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Rack/operation/get-rack-task): Retrieve the status of the specified rack task.

### Tray Endpoints

- [GET /v2/org/{org}/carbide/tray](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Tray/operation/get-all-trays): Get all trays (components) for the specified site.
- [GET /v2/org/{org}/carbide/tray/{id}](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Tray/operation/get-tray): Retrieve a tray (component) with the specified ID.
- [GET /v2/org/{org}/carbide/tray/validation](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Tray/operation/validate-trays): Validate tray components by comparing the expected state to the actual state. If no filter is specified, all trays in the site are validated.
- [GET /v2/org/{org}/carbide/tray/{id}/validation](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Tray/operation/validate-tray): Validate the components of the specified tray by comparing the expected state to the actual state.
- [PATCH /v2/org/{org}/carbide/tray/power](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Tray/operation/power-control-trays): Control the power of all trays using the optional name filter. If no filter is specified, all trays in the site are updated. Supported power states are `on`, `off`, `cycle`, `forceoff`, `forcecycle`.
- [PATCH /v2/org/{org}/carbide/tray/{id}/power](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Tray/operation/power-control-tray): Control the power of the specified tray. Supported power states are `on`, `off`, `cycle`, `forceoff`, `forcecycle`.
- [PATCH /v2/org/{org}/carbide/tray/firmware](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Tray/operation/firmware-update-trays): Update the firmware on all trays using the optional name filter. If no filter is specified, all trays in the site are updated.
- [PATCH /v2/org/{org}/carbide/tray/{id}/firmware](https://nvidia.github.io/ncx-infra-controller-rest/#tag/Tray/operation/firmware-update-tray): Update the firmware on the specified tray.