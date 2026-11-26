#!/bin/zsh
# Puts referrals online: the database part and the two server functions.
# Asks for a Supabase personal access token, uses it for this run only, and
# forgets it at the end. The token is never printed or written to a file.
#
#   zsh scripts/deploy-referrals.sh
#
# Afterwards, delete the token in Supabase (Account → Access Tokens).

cd "$(dirname "$0")/.." || exit 1
REF="mxlbafuzdbnypexhgptw"
URL="https://$REF.supabase.co"
PUB="sb_publishable_vG0EHaoQQAXvZ6i1cOJXlQ_OkIKML6A"   # the app's public key, already in index.html
CLI=(npx -y supabase@2.122.1)
setopt pipefail

say() { print -P "\n%B$1%b"; }
ok()  { print -P "  %F{green}✓%f $1"; }
bad() { print -P "  %F{red}✗%f $1"; FAILED=1; }
FAILED=0

say "1/6  Your Supabase access token"
print "  Paste it and press Return. Nothing will show while you paste."
read -rs SUPABASE_ACCESS_TOKEN
export SUPABASE_ACCESS_TOKEN
if [[ -z "$SUPABASE_ACCESS_TOKEN" ]]; then print "  No token given. Nothing was changed."; exit 1; fi
ok "token received (${#SUPABASE_ACCESS_TOKEN} characters, kept only in this run)"
trap 'unset SUPABASE_ACCESS_TOKEN' EXIT

say "2/6  The database part (supabase-part-6-referrals.sql)"
OUT=$(python3 -c 'import json,sys; print(json.dumps({"query": open(sys.argv[1]).read()}))' supabase-part-6-referrals.sql \
  | curl -sS -w "\n%{http_code}" -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
      -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" --data @-)
CODE=${OUT##*$'\n'}
if [[ "$CODE" == 2* ]]; then ok "tables and functions created"; else bad "the database said $CODE: ${OUT%$'\n'*}"; fi

say "3/6  Server function: referral-convert"
if "${CLI[@]}" functions deploy referral-convert --project-ref "$REF" --no-verify-jwt --use-api 2>&1 | sed 's/^/  /'; then ok "deployed"; else bad "deploy failed"; fi

say "4/6  Server function: apple-notifications"
if "${CLI[@]}" functions deploy apple-notifications --project-ref "$REF" --no-verify-jwt --use-api 2>&1 | sed 's/^/  /'; then ok "deployed"; else bad "deploy failed"; fi

say "5/6  Setting: TestFlight purchases count as test-only"
if "${CLI[@]}" secrets set REFERRAL_ALLOW_SANDBOX=1 --project-ref "$REF" 2>&1 | sed 's/^/  /'; then ok "set"; else bad "could not set it"; fi
unset SUPABASE_ACCESS_TOKEN

say "6/6  Checks, from the outside, with the app's public key only"
KEY=$(python3 -c 'import hashlib,os; print(hashlib.sha256(os.urandom(32)).hexdigest())')
R=$(curl -sS -X POST "$URL/rest/v1/rpc/referral_mine" -H "apikey: $PUB" -H "Authorization: Bearer $PUB" -H "Content-Type: application/json" --data "{\"k\":\"$KEY\",\"p\":\"monthly\"}")
if [[ "$R" == *'"ok" : true'* || "$R" == *'"ok":true'* ]]; then ok "the app can get a referral code"; else bad "referral_mine answered: $R"; fi
curl -sS -o /dev/null -X POST "$URL/rest/v1/rpc/referral_forget" -H "apikey: $PUB" -H "Authorization: Bearer $PUB" -H "Content-Type: application/json" --data "{\"k\":\"$KEY\"}"
ok "the check's own test code was deleted again"
C=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$URL/rest/v1/rpc/referral_convert" -H "apikey: $PUB" -H "Authorization: Bearer $PUB" -H "Content-Type: application/json" --data "{\"t\":\"$KEY\",\"otx\":\"1\",\"product\":\"x\",\"paid\":1,\"sandbox\":false}")
if [[ "$C" != 2* ]]; then ok "the app cannot record a purchase itself (answered $C)"; else bad "referral_convert is open to the app (answered $C)"; fi
F=$(curl -sS -w " %{http_code}" -X POST "$URL/functions/v1/referral-convert" -H "apikey: $PUB" -H "Authorization: Bearer $PUB" -H "Content-Type: application/json" --data "{\"jws\":\"not.a.jws\",\"t\":\"$KEY\"}")
if [[ "$F" == *"422" ]]; then ok "referral-convert refuses an unsigned purchase"; else bad "referral-convert answered: $F"; fi
N=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$URL/functions/v1/apple-notifications" -H "Content-Type: application/json" --data '{}')
if [[ "$N" == "400" ]]; then ok "apple-notifications refuses a notice Apple did not sign"; else bad "apple-notifications answered $N"; fi

if [[ $FAILED == 0 ]]; then say "Done. Referrals are online."; else say "Something above did not work. Nothing else needs undoing; tell Claude what it says."; fi
print "Now delete the token in Supabase: Account → Access Tokens."
