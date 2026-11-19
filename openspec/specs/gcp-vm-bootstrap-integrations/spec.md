## Requirements

### REQ-001: Bootstrap integration requirements SHALL be governed by cloud integration
Standalone bootstrap integration requirements SHALL be treated as consolidated into the cloud integration capability, and active requirement authority SHALL remain in openspec/specs/cloud-integration/spec.md.

#### Scenario: Requirement lookup resolves to cloud integration
- **GIVEN** an operator needs requirements for VM bootstrap convergence or onboarding behavior
- **WHEN** they reference this capability
- **THEN** they SHALL use openspec/specs/cloud-integration/spec.md as the normative source
- **AND** this capability SHALL be considered a compatibility redirect for historical traceability