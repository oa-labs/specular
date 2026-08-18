# Home visual system

This guide describes the visual language used by Specular's primary home
views: Daily, All, Meetings, and People. It is intended to keep new home
features feeling calm, deliberate, and consistent across Android and macOS.

## Design intent

The home experience should prioritize reading and writing notes over chrome.
Navigation and filters must be easy to find, but should not compete with note
content. Use a small number of repeated visual decisions—shared edges, soft
surfaces, restrained color, and predictable spacing—rather than introducing a
new treatment for each view.

## Layout and spacing

- Keep home content in one aligned column. On wide windows, constrain it to a
  maximum width of 840 logical pixels; on phones, let it fill the available
  width.
- Align tabs, search, banners, and note cards to the same 16-pixel horizontal
  inset.
- Separate major regions with deliberate whitespace. The tab control sits
  below the app bar; the All search field has 20 pixels above and below it;
  lists begin without an additional heavy divider.
- Use 10–12 pixels between related cards and 16–20 pixels before a new
  section or control group.

## Navigation and search

- Treat the four home views as a true segmented control. All segments share a
  44-pixel touch target, a common outline, and one selected state. Do not mix
  segmented controls with underlines or unrelated tab treatments.
- The selected segment uses a tonal container, stronger text weight, and
  higher-contrast foreground. Unselected segments stay quiet but legible.
- The All view search field is a compact 48-pixel control with a 14-pixel
  radius, subtle tonal fill, search icon, focused outline, and a clear action
  when text is present. It filters as the user types.

## Surfaces and note hierarchy

- Prefer softly toned cards over full-width rows divided by heavy lines.
  Home cards use a 14-pixel radius, no elevation, and a low-contrast outline.
- Make titles the strongest text in each card. Keep the preview or summary
  muted, clamp it to the useful amount of content, and put low-priority facts
  such as the update date in small, subdued metadata text.
- Keep icons purposeful: they identify note kind, pin state, or an actionable
  condition. They should not become decoration.
- Strip presentation-only Markdown syntax from note titles in list views. A
  title should read cleanly before a note is opened.

## Daily view

- Daily uses the same content width, tab treatment, card radius, surface, and
  outline as the other home views, while retaining a writing-first canvas.
- Give today's day card a gentle tonal accent and an explicit `TODAY` marker.
  The distinction should be noticeable without overpowering the editor.
- In the mobile week picker, show today with a tonal outlined date cell even
  when another date is selected. If today's week is not visible, show a
  persistent Today shortcut that returns to it in one tap.
- Render daily previews and scheduled-task text as Markdown. Reuse the shared
  Markdown and wiki-link handling so emphasis, links, and task state look the
  same as elsewhere in the app.

## Interaction, accessibility, and platform behavior

- Preserve at least 44-pixel targets for interactive controls. Give icon-only
  actions tooltips or semantic labels, including Clear search and Today.
- Use tonal color and text weight together for selected, focused, and current
  states; do not rely on color alone.
- Keep the behavior and information hierarchy shared in Flutter on Android and
  macOS. Adapt only the available width: macOS gains the constrained column;
  phones retain full-width controls and the mobile date picker.
- Maintain native expectations: touch-friendly controls on Android, and clear
  focus, hover, keyboard, and text-selection behavior on macOS where the
  underlying component supports it.

## When extending the home views

Before adding a new control or panel, first ask whether it belongs in the
existing content column and can reuse the existing card or segmented-control
treatment. Add visual emphasis only when it communicates a meaningful state,
such as the selected view, current day, focused search field, conflict, or
pending backup. This keeps the home screen useful as a note library grows
without making it feel busy.
