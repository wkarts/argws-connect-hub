# frozen_string_literal: true
module HubAdminUiHelper
  ICONS = {
    'icon-grid-line' => ['M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z'],
    'icon-building-4-line' => ['M4 21V3h11v18 M15 9h5v12 M2 21h20 M8 7h3 M8 11h3 M8 15h3 M8 21v-3h3v3'],
    'icon-user-follow-line' => ['M15 21v-2a6 6 0 0 0-12 0v2 M9 3a4 4 0 1 0 0 8a4 4 0 0 0 0-8 M16 10l2 2 4-4'],
    'icon-apps-2-line' => ['M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z'],
    'icon-robot-line' => ['M5 7h14v13H5z M9 12h.01 M15 12h.01 M9 16h6 M12 7V3 M10 3h4 M2 11v5 M22 11v5'],
    'icon-folder-3-line' => ['M3 6h7l2 3h9v11H3z M3 6V4h7l2 2h9v3'],
    'icon-draft-line' => ['M5 3h9l5 5v13H5z M14 3v6h5 M8 13h8 M8 17h6'],
    'icon-reply-line' => ['M9 5L3 11l6 6 M3 11h11a7 7 0 0 1 7 7'],
    'icon-tools-line' => ['M14 4a6 6 0 0 0-7 7L2 16a3 3 0 0 0 4 4l5-5a6 6 0 0 0 8-7l-4 4-4-4z'],
    'icon-settings-2-line' => ['M4 6h16 M4 12h16 M4 18h16 M8 3v6 M16 9v6 M10 15v6'],
    'icon-mist-fill' => ['M4 5h16 M4 10h16 M4 15h11 M4 20h7'],
    'icon-health-book-line' => ['M3 4h18v16H3z M6 12h3l2-5 3 9 2-4h2'],
    'icon-plug-connected-line' => ['M8 3v5 M16 3v5 M5 8h14 M7 8v4a5 5 0 0 0 10 0V8 M12 17v4'],
    'icon-dashboard-line' => ['M4 20a10 10 0 1 1 16 0z M12 15l5-7 M12 15h.01'],
    'icon-logout-circle-r-line' => ['M10 3H4v18h6 M9 12h12 M17 8l4 4-4 4'],
    'hub-diagnostics' => ['M4 3h16v18H4z M7 8h10 M7 12h5 M7 16h3 M15 16l2 2 3-4'],
    'hub-link' => ['M10 14l4-4 M8 16l-2 2a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0 M16 8l2-2a4 4 0 0 1 6 6l-5 5a4 4 0 0 1-6 0']
  }.freeze
  def hub_admin_icon(name)
    paths = ICONS.fetch(name.to_s, ICONS['icon-apps-2-line'])
    content_tag(:svg, viewBox: '0 0 24 24', width: 18, height: 18, fill: 'none', stroke: 'currentColor',
                'stroke-width': 1.7, 'stroke-linecap': 'round', 'stroke-linejoin': 'round',
                'aria-hidden': true, focusable: false, class: 'hub-nav-icon') do
      safe_join(paths.map { |path| tag.path(d: path) })
    end
  end
end
