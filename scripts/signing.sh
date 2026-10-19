# Sourced by build.sh and test.sh, which both build the app: the test
# action rebuilds it too, and an ad hoc copy would lose the Accessibility grant.
# A stable local identity keeps privacy permissions (Accessibility) across
# rebuilds; ad hoc signatures change on every build and macOS forgets them.
SIGN_IDENTITY="Pivot Dev"
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY")
else
  echo "Certificat « $SIGN_IDENTITY » absent : signature ad hoc (Accessibilité à réautoriser après chaque build)." >&2
  SIGN_ARGS=()
fi
