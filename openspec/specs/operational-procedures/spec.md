## Requirements

### REQ-001: NPM reverse proxy mandated for all external services
Every service that is accessible from outside the Docker host SHALL be routed through Nginx Proxy Manager. Direct port exposure (`ports:` directives) for externally accessible services SHALL be commented out in `docker-compose.yml`. This requirement applies to all service categories.

#### Scenario: New service is made externally accessible via NPM
- **GIVEN** an operator adds a service intended for external access
- **WHEN** they configure routing
- **THEN** they SHALL add the service's category network to NPM's compose file, comment out the service's `ports:` directive, verify NPM shares the network, and configure an NPM proxy host
- **AND** no active `ports:` mapping SHALL exist for that service after the NPM proxy host is live

#### Scenario: Port exposure audit passes
- **GIVEN** all `docker-compose.yml` files in the repository are scanned
- **WHEN** checking for active host port mappings
- **THEN** no service intended for external access SHALL have an uncommented `ports:` mapping that bypasses NPM

### REQ-002: NPM network membership covers all externally accessible categories
NPM SHALL be connected to all named service networks that contain externally accessible services. The network list SHALL be updated whenever a new service category is introduced.

#### Scenario: NPM is verified to join all required networks
- **GIVEN** `docker inspect npm` is executed
- **WHEN** reviewing the networks section
- **THEN** all active category networks SHALL be listed
- **AND** any new category network SHALL be added to NPM's network list before the first externally accessible service in that category is deployed

### REQ-003: Rollback procedure is documented and executable without external tools
The homelab SHALL maintain a rollback procedure for service configuration changes that requires only `docker` and `git` commands available on the host.

#### Scenario: Rollback to previous image is documented
- **GIVEN** a service container update causes a regression
- **WHEN** the operator follows the rollback procedure
- **THEN** they SHALL be able to revert to the previous container image using only `docker` and `git` commands
- **AND** the procedure SHALL not require network access to external tools

### REQ-004: Change management procedure prevents untested deployments
The homelab SHALL maintain a change management procedure that requires testing changes in isolation before applying them to all services.

#### Scenario: Single-service test precedes full deployment
- **GIVEN** a configuration change is proposed for one or more services
- **WHEN** the operator follows the change management procedure
- **THEN** they SHALL test the affected service in isolation using `docker compose up -d <service>` before applying the change to dependent or downstream services

### REQ-005: Security maintenance procedure is documented
The homelab SHALL maintain a security maintenance procedure covering: container image update workflow, secret rotation steps, and certificate validity verification.

#### Scenario: Monthly image update is performed safely
- **GIVEN** an operator follows the monthly security maintenance procedure
- **WHEN** pulling and applying updated container images
- **THEN** they SHALL verify service health after each critical service update before proceeding to the next
- **AND** the procedure SHALL document how to identify and skip containers excluded from Watchtower

### REQ-006: Disaster recovery procedure is documented
The homelab SHALL maintain a disaster recovery procedure for complete host loss, covering: git clone, dependency installation, cloud backup retrieval, database restore, volume restore, and service restart in dependency order.

#### Scenario: Complete host recovery procedure is documented
- **GIVEN** the homelab host is lost and must be rebuilt
- **WHEN** the operator follows the disaster recovery procedure
- **THEN** it SHALL provide an ordered sequence from bare OS to fully running services
- **AND** each step SHALL reference the relevant service-specific RESTORE_GUIDE.md
