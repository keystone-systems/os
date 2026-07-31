# Portfolio Review - March 2026

| Date | Active projects |
| --- | --- |
| 2026-03-31 | 7 |

| Open milestones | Overall health |
| --- | --- |
| 14 | 🟡 Mixed momentum with one urgent blocker and several strategic follow-ups. |

## Portfolio summary

Keystone and nixos-config need immediate attention because they are both important and time-sensitive. Catalyst and obsidian are important, but can be scheduled deliberately. A few low-signal projects should be delegated or archived to reduce cognitive load.

<div class="note-box">
  <div class="note-box-title">Summary notes</div>
  <div class="note-lines"></div>
</div>

## Project status

| Project | Status | Active Milestone | Progress | Activity | Top Blocker |
| --- | --- | --- | --- | --- | --- |
| keystone | 🟡 At Risk | Desktop Integration | 67% | High (23) | Installer TUI |
| nixos-config | 🟡 At Risk | Fleet cleanup | 58% | Medium (5) | Flake drift |
| catalyst | 🟢 On Track | Cloud platform | 45% | Medium (8) | None |
| obsidian | 🟢 On Track | ZK migration | 35% | Medium (6) | Review backlog |
| plant-caravan | 🟡 At Risk | Launch prep | 20% | Low (2) | Missing owner |
| meze | ⚪ Deferred | None | None | Stagnant (0) | No active work |
| eonmun | ⚪ Deferred | None | None | Stagnant (0) | No active work |

## Portfolio priority matrix

<table class="eisenhower-matrix">
  <colgroup>
    <col class="axis-col" />
    <col class="quadrant-col" />
    <col class="quadrant-col" />
  </colgroup>
  <thead>
    <tr>
      <th></th>
      <th>Urgent</th>
      <th>Not urgent</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>Imp.</th>
      <td class="quadrant quadrant-q1">
        <div class="quadrant-heading">Q1 - Do first</div>
        <ul>
          <li>keystone - Desktop integration, 67%, installer TUI blocking validation</li>
          <li>nixos-config - Fleet cleanup, 58%, flake drift affecting host updates</li>
        </ul>
      </td>
      <td class="quadrant quadrant-q2">
        <div class="quadrant-heading">Q2 - Schedule</div>
        <ul>
          <li>catalyst - Cloud platform, 45%, healthy momentum with no blocker</li>
          <li>obsidian - ZK migration, 35%, important but not time sensitive this week</li>
        </ul>
      </td>
    </tr>
    <tr>
      <th>Not imp.</th>
      <td class="quadrant quadrant-q3">
        <div class="quadrant-heading">Q3 - Delegate</div>
        <ul>
          <li>plant-caravan - Launch prep, 20%, needs explicit owner before more work</li>
        </ul>
      </td>
      <td class="quadrant quadrant-q4">
        <div class="quadrant-heading">Q4 - Eliminate / Archive</div>
        <ul>
          <li>meze - No milestones, no active work</li>
          <li>eonmun - No milestones, no active work</li>
          <li>tetrastack - No milestones, no active work</li>
          <li>ks-hw - No milestones, no active work</li>
        </ul>
      </td>
    </tr>
  </tbody>
</table>

<div class="note-box">
  <div class="note-box-title">Matrix notes</div>
  <div class="note-lines note-lines-tall"></div>
</div>

## Per-project example

### keystone

**Status**: 🟡 At Risk
**Activity**: High (23 commits in 30 days, last: 2026-03-29)

<table class="eisenhower-matrix eisenhower-matrix-compact">
  <colgroup>
    <col class="axis-col" />
    <col class="quadrant-col" />
    <col class="quadrant-col" />
  </colgroup>
  <thead>
    <tr>
      <th></th>
      <th>Urgent</th>
      <th>Not urgent</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>Imp.</th>
      <td class="quadrant quadrant-q1">
        <div class="quadrant-heading">Q1 - Do first</div>
        <ul>
          <li>Desktop Integration - 67%, due 2026-04-01</li>
        </ul>
      </td>
      <td class="quadrant quadrant-q2">
        <div class="quadrant-heading">Q2 - Schedule</div>
        <ul>
          <li>Ext4 hibernation design - 20%, no due date</li>
        </ul>
      </td>
    </tr>
    <tr>
      <th>Not imp.</th>
      <td class="quadrant quadrant-q3">
        <div class="quadrant-heading">Q3 - Delegate</div>
        <ul>
          <li>Docs cleanup - 10%, can be delegated</li>
        </ul>
      </td>
      <td class="quadrant quadrant-q4">
        <div class="quadrant-heading">Q4 - Eliminate / Archive</div>
        <ul>
          <li>None</li>
        </ul>
      </td>
    </tr>
  </tbody>
</table>

<div class="note-box">
  <div class="note-box-title">Project notes</div>
  <div class="note-lines"></div>
</div>
