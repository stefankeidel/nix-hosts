{ pkgs, ... }:

{
  programs.helix = {
    enable = true;
    settings = {
      theme = "material_deep_ocean";
      #editor.line-number = "relative";
      editor.cursor-shape = {
        normal = "block";
        insert = "bar";
        select = "underline";
      };
    };
  };
}
