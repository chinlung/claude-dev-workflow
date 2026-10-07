# scope-parse.awk — the single grammar for the scope-ledger files.
#
#   awk -f scope-parse.awk -v kind=followups FILE      # .claude/scope-followups.local.md
#   awk -f scope-parse.awk -v kind=ledger    FILE      # .claude/scope-ledger.local.md
#
# Why a parser instead of per-hook grep: the hooks used to decide "what counts as an open item" with
# their own one-line patterns, so a line that was subtly wrong (a missing space after HIGH, a missing
# 去處 field) was silently counted, silently dropped, or both — depending on which hook looked at it —
# and the same file was read by other tools with a stricter grammar (Pi's parseFollowups rejects the
# whole file on one bad line). Here the grammar lives in one place, every line is classified, and the
# output says why a line was rejected.
#
# Output: one record per line of stdout, TAB-separated, first field is the record type. TAB is replaced by a
# space in every value, so every record has a fixed number of fields; a CR at the end of a line is dropped, a
# CR inside a line is kept (records are split on newline only, so it cannot forge a record).
#
#   E line done date sev text from source dest raw     follow-up entry (checkbox + date + severity recognised)
#   I line done text source raw                        In scope entry (top-level "- [ ]" / "- [x]" line)
#   D line text source sev reason dest raw             Deferred entry (top-level "- " line)
#   F key value                                        frontmatter field
#   S section line raw                                 every line of frontmatter / In scope / Deferred / Log, verbatim
#   X line class open reason                           a problem. class: warn = recognised but incomplete (still
#                                                      counted); bad = not recognisable (not counted). open = 1
#                                                      when the line is an unticked item, so a would-be to-do
#                                                      never disappears without a trace. `reason` is a fixed
#                                                      phrase — never the line's own text, which would replay
#                                                      file content into the model's context.
#
# Grammar (follow-ups; same shape as Pi's parseFollowups):
#   line 1:  "# scope-ledger follow-ups"
#   entry:   - [ ] YYYY-MM-DD HIGH|MEDIUM|LOW <text> ← from: <from> ｜ 來源: <source> ｜ 去處: <dest>
#            "|" for "｜", "source:" for "來源:", "where:" for "去處:" are accepted; a trailing
#            `<!-- scope:<kind> {...} -->` metadata comment (written by Pi) is ignored.
# Grammar (ledger): see skills/scope/SKILL.md — frontmatter between --- fences; "## In scope" lines
#   "- [ ] <item> ← 來源: <source>"; "## Deferred" lines "- <item> ← 來源: <s> ｜ 嚴重度: <S> ｜ 理由: <r> ｜ 去處: <d>".
#   Indented lines inside a section are sub-items or notes and are ignored.
#
# Portability: runs on BWK awk (macOS), mawk (Debian/Ubuntu default) and gawk. No {n} intervals (mawk),
# no multibyte characters inside bracket expressions (byte-oriented awks), no gawk-only functions.

function clean(s) { sub(/\r$/, "", s); gsub(/\t/, " ", s); return s }
# Linear-time trim. `sub(/[ ]+$/, …)` is quadratic on a long run of spaces (the regex is retried from every
# position of the run), which let a 50KB line of blanks outlast the hook's 10-second timeout under BWK awk.
function rtrim(s,    i) {
  i = length(s)
  while (i > 0 && substr(s, i, 1) == " ") i--
  return substr(s, 1, i)
}
function trim(s) { sub(/^[ ]+/, "", s); return rtrim(s) }
# Strip only the LAST `<!-- scope:… -->`, and only when the line ends with it. Pi's comment() escapes every "-"
# inside its JSON body, so the last such marker is always the real trailing metadata; a text that merely quotes
# the marker mid-line (and a line that starts with one) must keep everything around it.
function strip_meta(s,    p) {
  if (s !~ / -->$/) return s
  p = lastpos(s, "<!-- scope:")
  if (p > 0 && substr(s, p) ~ /^<!-- scope:[A-Za-z0-9_]+ .* -->$/) s = rtrim(substr(s, 1, p - 1))
  return s
}
function prob(n, cls, op, why) { print "X", n, cls, op, why }
function addwhy(cur, w) { return (cur == "") ? w : cur "；" w }

# Position of the LAST occurrence of marker in s (0 when absent): an item's own text may contain "←".
# Linear: split() cuts the string once; a loop that re-copies the remainder with substr() is O(n·k) and took
# 25 seconds on a 1MB line of repeated markers under gawk. The markers used here contain no regex metacharacters
# (split treats a multi-character separator as a regex).
function lastpos(s, marker,    n, parts) {
  n = split(s, parts, marker)
  if (n < 2) return 0
  return length(s) - length(parts[n]) - length(marker) + 1
}

# ---------------------------------------------------------------------------- follow-ups
function followup(n, raw,    line, c, done, date, rest, sev, body, i, tail, r2, text, from, src, dest, why) {
  line = strip_meta(raw)
  if (line ~ /^[ ]*$/) return
  if (substr(line, 1, 3) != "- [") { prob(n, "bad", 0, "非清單行（須以 - [ ] 或 - [x] 開頭）"); return }
  c = substr(line, 4, 1)
  if (substr(line, 5, 2) != "] " || (c != " " && c != "x" && c != "X")) {
    prob(n, "bad", 0, "勾選框須為 [ ] 或 [x]，其後一個空格"); return
  }
  done = (c == " ") ? 0 : 1
  date = substr(line, 7, 10)
  if (date !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ || substr(line, 17, 1) != " ") {
    prob(n, "bad", !done, "日期須為 YYYY-MM-DD，其後一個空格"); return
  }
  rest = substr(line, 18)
  if (rest !~ /^(HIGH|MEDIUM|LOW)( |$)/) {
    prob(n, "bad", !done, "嚴重度須為 HIGH／MEDIUM／LOW，其後一個空格"); return
  }
  sev = rest; sub(/[ ].*$/, "", sev)
  body = " " substr(rest, length(sev) + 2)      # leading space so "← from:" may start the body (empty text)
  why = ""; from = ""; src = ""; dest = ""
  i = index(body, " ← from: ")
  if (i == 0) {
    text = trim(body); why = "缺 ← from:、來源:、去處:"
  } else {
    text = trim(substr(body, 1, i - 1))
    tail = substr(body, i + length(" ← from: "))
    if (match(tail, /(｜|\|)[ ]*(來源|source):[ ]*/)) {
      from = trim(substr(tail, 1, RSTART - 1)); r2 = substr(tail, RSTART + RLENGTH)
      if (match(r2, /(｜|\|)[ ]*(去處|where):[ ]*/)) {
        src = trim(substr(r2, 1, RSTART - 1)); dest = trim(substr(r2, RSTART + RLENGTH))
        if (src == "") why = addwhy(why, "來源: 為空")
        if (dest == "") why = addwhy(why, "去處: 為空")
      } else {
        src = trim(r2); why = addwhy(why, "缺 去處:")
      }
    } else if (match(tail, /(｜|\|)[ ]*(去處|where):[ ]*/)) {
      from = trim(substr(tail, 1, RSTART - 1)); dest = trim(substr(tail, RSTART + RLENGTH))
      why = addwhy(why, "缺 來源:")
    } else {
      from = trim(tail); why = addwhy(why, "缺 來源:、去處:")
    }
    if (from == "") why = addwhy(why, "← from: 為空")
  }
  if (text == "") why = addwhy(why, "項目文字為空")
  print "E", n, done, date, sev, text, from, src, dest, line
  if (why != "") prob(n, "warn", !done, why)
}

# ---------------------------------------------------------------------------- ledger
function check_frontmatter(    v) {
  if (!("goal" in fmval) || fmval["goal"] == "") prob(1, "warn", 0, "缺 goal")
  if ("mode" in fmval) {
    v = trim(fmval["mode"])
    if (v != "converge" && v != "harvest") prob(fmline["mode"], "warn", 0, "mode 須為 converge 或 harvest")
  }
  if ("review_rounds" in fmval) {
    v = trim(fmval["review_rounds"])
    if (v !~ /^[0-9]+$/) prob(fmline["review_rounds"], "warn", 0, "review_rounds 須為非負整數")
  }
}

function inscope(n, line,    c, done, body, last, text, src, why) {
  if (substr(line, 1, 3) != "- [") { prob(n, "bad", 0, "非清單行（頂層須為 - [ ] 或 - [x]）"); return }
  c = substr(line, 4, 1)
  if (substr(line, 5, 2) != "] " || (c != " " && c != "x" && c != "X")) {
    prob(n, "bad", 0, "勾選框須為 [ ] 或 [x]，其後一個空格"); return
  }
  done = (c == " ") ? 0 : 1
  body = substr(line, 7); why = ""
  last = lastpos(body, " ← 來源: ")
  if (last > 0) {
    text = trim(substr(body, 1, last - 1)); src = trim(substr(body, last + length(" ← 來源: ")))
    if (src == "") why = "來源: 為空"
  } else {
    text = trim(body); src = ""; why = "缺 ← 來源:"
  }
  print "I", n, done, text, src, line
  if (why != "") prob(n, "warn", !done, why)
}

function deferred(n, line,    body, last, text, tail, parts, np, k, p, src, sv, rs, ds, why, stray) {
  if (substr(line, 1, 2) != "- ") { prob(n, "bad", 0, "非清單行（Deferred 的頂層行須以 - 開頭）"); return }
  body = substr(line, 3); why = ""; src = ""; sv = ""; rs = ""; ds = ""
  last = lastpos(body, " ← 來源: ")
  if (last == 0) {
    text = trim(body); why = "缺 ← 來源:"
  } else {
    text = trim(substr(body, 1, last - 1)); tail = substr(body, last + length(" ← 來源: "))
    np = split(tail, parts, /(｜|\|)/)
    src = trim(parts[1])
    for (k = 2; k <= np; k++) {
      p = trim(parts[k])
      if (index(p, "嚴重度:") == 1) sv = trim(substr(p, length("嚴重度:") + 1))
      else if (index(p, "理由:") == 1) rs = trim(substr(p, length("理由:") + 1))
      else if (index(p, "去處:") == 1) ds = trim(substr(p, length("去處:") + 1))
      else if (p != "") stray = 1     # a value that itself contains ｜ or | was cut in two: say so instead of truncating silently
    }
    if (stray) why = addwhy(why, "有無法辨識的欄位片段（值裡含 ｜ 或 | ？）")
    if (sv == "") why = addwhy(why, "缺 嚴重度:")
    else if (sv != "HIGH" && sv != "MEDIUM" && sv != "LOW") why = addwhy(why, "嚴重度須為 HIGH／MEDIUM／LOW")
    if (rs == "") why = addwhy(why, "缺 理由:")
    if (ds == "") why = addwhy(why, "缺 去處:")
  }
  print "D", n, text, src, sv, rs, ds, line
  if (why != "") prob(n, "warn", 0, why)
}

function ledger_line(n, raw,    line, h, key, val) {
  if (n == 1) {
    if (raw == "---") { fm = 1; print "S", "frontmatter", n, raw; return }
    prob(1, "bad", 0, "缺 frontmatter（首行須為 ---）")     # then keep parsing the body: sections still work
  }
  if (fm) {
    print "S", "frontmatter", n, raw
    if (raw == "---") { fm = 0; check_frontmatter(); return }
    if (match(raw, /^[A-Za-z_][A-Za-z0-9_]*:/)) {
      key = substr(raw, 1, RLENGTH - 1); val = substr(raw, RLENGTH + 1); sub(/^[ \t]+/, "", val)
      print "F", key, val
      fmline[key] = n; fmval[key] = val
    }
    return
  }
  if (raw ~ /^## /) {
    h = substr(raw, 4)
    sect = (h == "In scope" || h == "Deferred" || h == "Log") ? h : "other"
    return
  }
  if (sect == "" || sect == "other") return                # before the first heading, or a section we do not read
  print "S", sect, n, raw
  line = strip_meta(raw)
  if (line ~ /^[ ]*$/) return
  if (line ~ /^[ \t]/) return                              # indented: sub-item or note, not a top-level line
  if (sect == "In scope") inscope(n, line)
  else if (sect == "Deferred") deferred(n, line)
}

BEGIN {
  OFS = "\t"
  if (kind != "followups" && kind != "ledger") {
    print "scope-parse.awk: pass -v kind=followups or -v kind=ledger" > "/dev/stderr"
    bad_usage = 1; exit 2
  }
  fm = 0; sect = ""
  BOM = "\357\273\277"          # UTF-8 byte order mark
}

{
  raw = clean($0)
  # A BOM on line 1 (Windows editors add one) would defeat the header / "---" comparisons. Pi's reader drops it
  # (TextDecoder), so the two readers must agree. index()+substr(), not a regex: a regex literal of these bytes does
  # not match under BWK awk in a UTF-8 locale; index/substr are consistent per implementation (bytes or characters).
  if (NR == 1 && index(raw, BOM) == 1) raw = substr(raw, length(BOM) + 1)
  if (kind == "followups") {
    if (NR == 1 && raw != "# scope-ledger follow-ups") {
      prob(1, "bad", 0, "標頭須為 # scope-ledger follow-ups")
      if (raw ~ /^- \[/) followup(NR, raw)                 # a file whose first line is an entry keeps that entry
      next
    }
    if (NR == 1) next
    followup(NR, raw)
  } else {
    ledger_line(NR, raw)
  }
}

END {
  if (bad_usage) exit 2
  if (kind == "ledger" && fm) prob(NR, "bad", 0, "frontmatter 未以 --- 收尾")
}
