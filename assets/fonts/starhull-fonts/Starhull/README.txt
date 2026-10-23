Starhull v1.1 - pixel font
by fcidade

Thanks for downloading! License: see LICENSE.txt (commercial use allowed).


FILES

  Starhull.ttf
      TrueType font. Crisp at 13px and its multiples (13, 26, 39...).

  Starhull.fnt
      BMFont (text format), uses Starhull.png. Works in Godot, Phaser, LOVE,
      MonoGame, libGDX, Defold and others.

  Starhull.png
      Spritesheet: white glyphs on transparent background, 16 per row,
      9x13px cells. Tint it any color in your engine.

  Starhull-chars.txt
      The characters in the spritesheet, in order.


CHARACTER SET

  196 glyphs: ASCII, Latin-1 and the euro sign. Covers English, Portuguese,
  Spanish, French, German, Italian and most Western European languages.


QUICK START

  Godot 4
    BMFont: put Starhull.fnt and Starhull.png in the same folder of your project
    (the .fnt needs the .png next to it) and use the .fnt as the font of
    a Label.
    TTF: in the .ttf import settings set Antialiasing to None and
    Subpixel Positioning to Disabled, then use font size 13 or a multiple.

  Unity
    Import Starhull.ttf and use a font size that is a multiple of 13. Set the
    font texture filter to Point (no filter) to keep the pixels sharp.

  GameMaker
    Import Starhull.png as a sprite strip (196 frames, 16 per row,
    9x13 each), then create the font with font_add_sprite_ext(),
    passing the contents of Starhull-chars.txt as the string map.

  Anything else
    Use the .ttf at 13px or a multiple, with antialiasing / smoothing off.
