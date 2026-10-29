# User interface preferences

These are explicit preferences from the project owner. Preserve them in future UI work:

- Keep the Starhull font. Render bitmap text at crisp pixel sizes; fix layout and scaling rather than substituting a different body font.
- Avoid hover tooltips. The conditional lock explanation over Ship Designer is the exception the user accepts. Show necessary prices, restrictions and feedback inline or in a panel opened by clicking.
- Keep the five Fleet ship slots and common controls visible without scrolling at the supported sizes, including 640×360.
- Put actions for an individual physical ship beside that ship in the formation view, only while exactly one ship is selected. Do not repeat Reserve/Deploy buttons for every ship in the fleet summary.
- No Tab or arrow-key cycling between UI controls, and no focus-outline boxes on buttons, tabs, sliders or texture controls. Text fields still accept typing and canvas/gameplay shortcuts remain available.
- UI fonts and reusable component styles belong in `themes/ui_theme.tres`; use theme inheritance/type variations instead of per-control font resources, fallback fonts or copied style boxes. Changing the theme's default font should update the UI.
- Reserved ships are absent from formation rendering and hit testing. Manage them in a small modal opened by a Reserve button.
- Do not add unrequested features while implementing remaining milestones. Ask before adding a feature outside the requested scope.
- Do not offer individual construction-material purchases. Construction/repair and other material-consuming actions use owned materials first, then charge credits for shortages at the existing material exchange rates. Credits act as material wild cards; this is separate from the planned cargo-goods trade.
