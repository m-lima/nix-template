let
  override =
    overrider: default:
    if builtins.isNull overrider then
      default
    else if builtins.isFunction overrider then
      overrider default
    else if builtins.isList default then
      default ++ overrider
    else if builtins.isAttrs default then
      default // overrider
    else
      overrider;
in
{
  inherit override;

  tryOverride =
    overrides: name: default:
    if builtins.hasAttr name overrides then override overrides.${name} default else default;

  fmtSettings = extra: fmtExcludes: {
    on-unmatched = "warn";
    excludes = [
      "**/.direnv/*"
      "**/.envrc"
      "**/.gitignore"
      "*.lock"
      ".direnv/*"
      ".envrc"
      ".git-crypt/*"
      ".gitattributes"
      ".gitignore"
      "LICENSE"
      "result*/*"
    ]
    ++ extra
    ++ fmtExcludes;
  };
}
