## Reads in oha output and creates a markdown table of stats

import std/[json, os, strutils]

type
  Summary = object
    successRate, total, slowest, fastest, average, requestsPerSec: float
  Stat = object
    summary: Summary

let
  baseline = parseFile(paramStr(1)).to(Stat).summary
  candidate = parseFile(paramStr(2)).to(Stat).summary

template formatVal(x: float): string = formatFloat(x, ffDecimal, 5)

template writeRow(metric: untyped, name: string, lowerBetter = true) =
  let
    diff = (when lowerBetter: -1 else: 1) * (candidate.metric - baseline.metric)
    percentage = formatFloat((diff / baseline.metric) * 100, ffDecimal, 2)
  echo "|", name, "|", formatVal(baseline.metric), "|", formatVal(candidate.metric), "|", percentage, "|"

echo "| Metric | Baseline | Candidate | Difference (%) |"
echo "|--------|----------|-----------|----------------|"
writeRow(successRate, "Success Rate")
writeRow(slowest, "Slowest")
writeRow(fastest, "Fastest")
writeRow(average, "Average")
writeRow(requestsPerSec, "Req/s", false)
