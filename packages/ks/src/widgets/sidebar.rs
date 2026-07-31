//! Navigation sidebar widget — stateless rendering primitive.

use ratatui::{
    layout::Rect,
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem},
    Frame,
};

/// A sidebar navigation entry.
pub struct SidebarItem {
    pub label: &'static str,
}

/// The standard navigation sections.
pub const NAV_ITEMS: &[SidebarItem] = &[
    SidebarItem { label: "Hosts" },
    SidebarItem { label: "Services" },
    SidebarItem { label: "Secrets" },
    SidebarItem { label: "Security" },
    SidebarItem { label: "Installer" },
];

/// Render the navigation sidebar. `active_index` highlights the current section.
pub fn render(frame: &mut Frame, area: Rect, active_index: usize) {
    let t = crate::theme::default();
    let items: Vec<ListItem> = NAV_ITEMS
        .iter()
        .enumerate()
        .map(|(i, item)| {
            let style = if i == active_index {
                t.active_style()
            } else {
                t.inactive_style()
            };
            ListItem::new(Line::from(Span::styled(format!(" {}", item.label), style)))
        })
        .collect();

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::RIGHT)
            .border_style(t.inactive_style()),
    );
    frame.render_widget(list, area);
}
