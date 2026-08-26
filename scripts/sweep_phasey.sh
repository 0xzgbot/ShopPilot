#!/bin/bash
# Sweep the PHASE Y cut-quality CLTs + nearest neighbours.
cd "$(dirname "$0")/.." || exit 1
for t in ShopPilotVerifyPhaseYAudit ShopPilotVerify2100a ShopPilotVerify2100b \
         ShopPilotVerify2100c ShopPilotVerify2100d ShopPilotVerify2110a \
         ShopPilotVerify2110b ShopPilotVerify2120a ShopPilotVerify2120b \
         ShopPilotVerify2120c ShopPilotVerify2010a ShopPilotVerify2010b \
         ShopPilotVerify2010c ShopPilotVerify3DGolden ShopPilotVerifyGolden25D \
         ShopPilotVerifyVCarveClear ShopPilotVerifySpecialty; do
  out=$(./scripts/verify_locked.sh "$t" 2>&1)
  res=$(printf '%s\n' "$out" | grep -Eo "$t: (PASS|FAIL.*)" | tail -1)
  if [ -z "$res" ]; then
    res=$(printf '%s\n' "$out" | grep -E 'PASS|FAIL|error:' | tail -1)
    [ -z "$res" ] && res="<no result>"
  fi
  printf '%-34s %s\n' "$t" "$res"
done
