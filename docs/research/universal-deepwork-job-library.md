---
title: "Universal DeepWork Job Library"
authors: "Unknown (AI-generated deep research via Gemini and ChatGPT)"
date: "2026-03-20"
source: "pasted content — two deep research reports generated from a structured research brief"
source_type: "deep_research"
tags:
  - deepwork
  - workflow-orchestration
  - multi-agent
  - job-catalog
  - reusable-steps
ingested: "2026-03-20"
slug: "universal-deepwork-job-library"
---

# Universal DeepWork Job Library

## Key Findings

- **118+ standardized jobs** cataloged across 17 domains (business, engineering, aerospace, medicine, security, education, agriculture, art, defense, architecture, and more), each decomposed into atomic reusable steps with workflow variants
- **7 universal reusable steps** identified that appear across 5+ jobs: `gather_sources` (20+), `write_report` (40+), `stakeholder_review` (30+), `synthesize` (15+), `compliance_check` (12+), `deep_research` (10+), and `check_citations` (5+)
- **Three meta-workflow patterns** emerge across all domains: "Research -> Analyze -> Report" (research-intensive), "Audit -> Gap -> Remediate" (compliance-oriented), and "Design -> Build -> Review -> Ship" (engineering-oriented)
- **Multi-agent parallelization** is consistently applicable during collection/development phases — independent tasks feeding the same objective are bracketed for concurrent execution across every domain
- **Quality gates as circuit breakers** — centralized approval checkpoints appear at critical junctures in every domain (CDR in aerospace, spec review in software, FDA approval in medicine), proving that while execution can be parallelized, approval remains a distinct centralized function

## Catalog

The full catalog of 118 jobs is in [jobs.yaml](jobs.yaml) — queryable with `yq`:

```bash
# List all jobs in a domain
yq '.jobs[] | select(.domain == "software_engineering") | .name' jobs.yaml

# Find jobs using a reusable step
yq '.jobs[] | select(.reusable_steps[] == "gather_sources") | .name' jobs.yaml

# Count jobs per domain
yq '[.jobs[] | .domain] | group_by(.) | map({(.[0]): length}) | add' jobs.yaml

# List all workflow names for a job
yq '.jobs[] | select(.name == "incident_response") | .workflows | keys' jobs.yaml

# Find jobs with concurrent steps
yq '.jobs[] | select(.workflows[].steps[] | type == "!!seq") | .name' jobs.yaml
```

### Example Job

```yaml
- name: incident_response
  summary: Incident detection, triage, resolution, and postmortem
  domain: software_engineering
  steps:
    [
      detect_alert,
      triage,
      assign_responders,
      investigate,
      mitigate,
      resolve,
      draft_postmortem,
      root_cause_analysis,
      action_items,
      publish_postmortem,
    ]
  reusable_steps: []
  workflows:
    full:
      steps:
        [
          detect_alert,
          triage,
          assign_responders,
          investigate,
          mitigate,
          resolve,
          draft_postmortem,
          root_cause_analysis,
          action_items,
          publish_postmortem,
        ]
      quality_gates: [resolve]
    response:
      steps:
        [
          detect_alert,
          triage,
          assign_responders,
          investigate,
          mitigate,
          resolve,
        ]
      quality_gates: []
    postmortem:
      steps:
        [
          draft_postmortem,
          root_cause_analysis,
          action_items,
          publish_postmortem,
        ]
      quality_gates: []
```

## Research Context

### Original Research Brief

The original research brief requested a comprehensive catalog of standardized DeepWork jobs and workflows enabling multiple agents to make coordinated progress across business, engineering, scientific, and operational missions. Each job was to be decomposed into reusable steps shareable across workflows.

The brief specified the DeepWork architecture primitives:

- **Job**: A named capability containing steps and workflows
- **Step**: An atomic unit of work with defined inputs, outputs, and instructions
- **Workflow**: A named execution path through a subset of a job's steps
- **Quality Gate**: Review criteria applied after step completion
- **Concurrent Steps**: Steps in brackets execute in parallel

The research covered 17+ domains: Business & Strategy, Competitive Intelligence, Finance, Software Engineering, Mechanical Engineering, Aerospace, Electrical Engineering, Art & Creative, Marketing, Medicine & Healthcare, Physical Security, Compliance & Legal, Geopolitical Affairs, Deep Space Missions, Operations & Project Management, Human Resources, Education & Training, plus cross-domain patterns including Robotics, Defense/Skunkworks, Agriculture/Botany/Horticulture, and Architecture/Urban Design.

---

### Jobs by Domain

All 118 jobs are in [jobs.yaml](jobs.yaml). Below is the index.

#### Business & Strategy (10)

- `lean_canvas` — Generate and validate a Lean Canvas
- `working_backwards` — Amazon-style press release and FAQ
- `business_model_validation` — Validate assumptions through evidence gathering
- `charter_mission` — Draft charter and mission statement
- `okr_kpi_framework` — Define OKRs and KPIs
- `stakeholder_map` — Map stakeholders by influence and interest
- `strategic_planning` — Quarterly or annual strategic planning
- `board_deck` — Board deck or investor update
- `partnership_evaluation` — Evaluate partnership opportunities
- `pricing_strategy` — Analyze and recommend pricing models

#### Competitive Intelligence & Market Research (7)

- `competitive_landscape` — Map the competitive landscape
- `swot_analysis` — SWOT analysis
- `market_sizing` — TAM, SAM, SOM estimation
- `customer_segmentation` — Identify and profile customer segments
- `win_loss_analysis` — Analyze won and lost deals
- `trend_forecast` — Identify and project trends
- `brand_positioning_audit` — Assess brand positioning

#### Finance & Investment (7)

- `financial_modeling` — DCF, comparables, scenario analysis
- `budget_variance` — Budget planning and variance analysis
- `investment_due_diligence` — Due diligence on target company or asset
- `portfolio_risk` — Portfolio risk exposure and concentration
- `cap_table_management` — Model and maintain cap table
- `fundraising_prep` — Pitch deck, data room, financial model
- `tax_compliance` — Tax planning and compliance review

#### Software Engineering (10)

- `spec_driven_development` — Design, implement, test, ship from spec
- `code_review` — Quality, security, and style checks
- `architecture_decision_record` — Document architectural decisions
- `incident_response` — Detection, triage, resolution, postmortem
- `cicd_pipeline` — Design and validate CI/CD pipelines
- `dependency_audit` — Security, licensing, staleness audit
- `api_design` — Design and validate API contracts
- `database_migration` — Plan and execute schema migrations
- `performance_profiling` — Identify bottlenecks, recommend optimizations
- `test_strategy` — Test strategy, coverage, infrastructure

#### Mechanical Engineering (6)

- `design_review` — FEA, tolerance, manufacturing analysis
- `bom_management` — Bill of materials lifecycle
- `manufacturing_process_plan` — Process sequence, tooling, quality
- `quality_control_inspection` — Inspection procedures and execution
- `fmea` — Failure mode and effects analysis
- `prototype_tracking` — Track prototype iterations

#### Aerospace Engineering (7)

- `mission_design` — Trajectory, launch window, delta-v budget
- `systems_requirements_verification` — Requirements traceability and verification
- `flight_readiness_review` — Go/no-go assessment
- `anomaly_investigation` — Root-cause and resolve anomalies
- `configuration_management` — Track configuration items through lifecycle
- `test_campaign` — Structured test campaign with traceability
- `launch_operations` — Integration through post-separation checklist

#### Electrical Engineering (6)

- `schematic_review` — Correctness, completeness, standards compliance
- `pcb_layout_review` — Signal integrity, thermal, DFM
- `power_budget` — Subsystem power consumption and margins
- `emc_compliance` — Electromagnetic compatibility
- `component_selection` — Select and validate components
- `test_fixture_design` — Board-level or system-level test fixtures

#### Art & Creative (6)

- `brand_identity` — Visual language, voice, guidelines
- `creative_brief` — Structured creative brief
- `asset_production` — Creative asset pipeline
- `exhibition_curation` — Exhibition or portfolio curation
- `critique_cycle` — Structured critique and revision
- `style_guide` — Visual and verbal style guide

#### Marketing (7)

- `campaign_planning` — Strategy through execution
- `content_calendar` — Content calendar across channels
- `seo_audit` — Technical and content SEO audit
- `social_media_strategy` — Platform-specific playbooks
- `email_marketing` — Campaigns and automations
- `launch_comms` — Launch communications coordination
- `analytics_attribution` — Performance and attribution models

#### Medicine & Healthcare (7)

- `patient_intake` — Virtual intake and triage
- `clinical_checklist` — WHO surgical safety and similar
- `emergency_response` — Emergency protocol execution
- `patient_history_review` — History review for clinical decision support
- `treatment_plan` — Evidence-based treatment plans
- `healthcare_compliance_audit` — HIPAA, trial protocol compliance
- `medical_literature_review` — Systematic or rapid literature review

#### Physical Security (6)

- `threat_assessment` — Threat to personnel, facilities, operations
- `site_security_audit` — Comprehensive physical security audit
- `access_control_policy` — Access control policy design
- `security_incident_response` — Incident response planning and execution
- `surveillance_design` — Surveillance system architecture
- `personnel_clearance` — Security clearance processing

#### Compliance & Legal (7)

- `regulatory_compliance_audit` — Audit against regulatory frameworks
- `contract_review` — Review, annotate, redline contracts
- `policy_drafting` — Draft, review, approve policies
- `risk_register` — Build and maintain risk register
- `privacy_impact_assessment` — GDPR, CCPA impact assessment
- `ip_review` — Patent, trademark, trade secret review
- `export_control` — Export control classification and licensing

#### Geopolitical Affairs & Policy (6)

- `country_risk_assessment` — Political, economic, security risk
- `sanctions_screening` — Screen against sanctions lists
- `political_stability_analysis` — Governance risk assessment
- `trade_policy_impact` — Tariff and trade agreement impact
- `diplomatic_engagement` — Diplomatic engagement planning
- `intelligence_briefing` — Structured intelligence briefing

#### Deep Space Missions (8)

- `mission_concept_study` — Phase A concept study
- `systems_engineering_review` — SRR, PDR, CDR equivalent
- `subsystem_trade_study` — Quantitative design trade studies
- `ground_segment_ops` — Ground segment operations planning
- `comms_link_budget` — Communication link budget analysis
- `radiation_assessment` — Radiation environment and shielding
- `autonomy_planning` — Long-duration mission autonomy
- `planetary_protection` — Planetary protection protocol compliance

#### Operations & Project Management (7)

- `project_charter` — Scope, stakeholders, success criteria
- `risk_management` — Identify, assess, mitigate risks
- `resource_planning` — Resource allocation and capacity
- `retrospective` — Retrospective or lessons learned
- `vendor_evaluation` — Vendor evaluation and procurement
- `change_management` — Organizational change management
- `sla_management` — SLA definition and monitoring

#### Human Resources & Talent (6)

- `job_description` — Structured job descriptions
- `interview_design` — Interview process with rubrics
- `onboarding` — Employee onboarding workflow
- `performance_review` — Performance review cycle
- `compensation_benchmarking` — Market data and internal equity
- `succession_planning` — Succession candidate development

#### Education & Training (5)

- `curriculum_design` — Curriculum with learning objectives
- `assessment_creation` — Assessments aligned to objectives
- `training_evaluation` — Training program effectiveness
- `knowledge_base` — Structured knowledge base
- `certification_pathway` — Certification with competency milestones
