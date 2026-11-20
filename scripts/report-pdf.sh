#!/usr/bin/env bash
# Собирает REPORT.pdf из REPORT.md через Quarto (движок Typst, без LaTeX) —
# как в ПР1. Добавляет титульный лист ИТМО (report-assets/title.typ.md) и чистит
# markdown под Typst (HTML-якоря, внутренние ссылки, @, эмодзи → надёжные глифы),
# не трогая исходный REPORT.md (он остаётся «чистым» для GitHub/просмотра).
#
# Запуск:  bash scripts/report-pdf.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/share/quarto/bin:$PATH"
command -v quarto >/dev/null || { echo "quarto не найден в PATH"; exit 1; }

SRC="REPORT.md"
BUILD="_report-build.md"

# 1) титульник + 2) обработанное тело → временный build-файл
cat report-assets/title.typ.md > "$BUILD"
python3 - "$SRC" >> "$BUILD" <<'PY'
import re, sys
md = open(sys.argv[1], encoding="utf-8").read()
md = re.sub(r'^# .*\n', '', md, count=1)                                   # первый H1 (его роль — титул)
md = re.sub(r'## Содержание.*?(?=<a id="ход-работы")', '', md, flags=re.S, count=1)  # ручное оглавление
md = re.sub(r'<a id="[^"]*"></a>\n?', '', md)                              # HTML-якоря
md = re.sub(r'\[([^\]]+)\]\(#[^)]+\)', r'\1', md)                          # внутренние ссылки [txt](#anchor) → txt
# эмодзи → надёжные глифы / текст
for a, b in (('✅','✓'),('✔️','✓'),('✔','✓'),('❌','✗'),('✖️','✗'),('⚠️','(!)'),('⚠','(!)')):
    md = md.replace(a, b)
md = re.sub(r'[\U0001F000-\U0001FAFF\U00002600-\U000027BF\U0001F1E6-\U0001F1FF️⏰❤]', '', md)  # прочие декоративные
# экранировать @ вне инлайн-кода (иначе Pandoc примет за цитату)
def esc(line):
    out, incode = [], False
    for c in line:
        if c == '`': incode = not incode; out.append(c)
        elif c == '@' and not incode: out.append('\\@')
        else: out.append(c)
    return ''.join(out)
md = '\n'.join(esc(l) for l in md.split('\n'))
sys.stdout.write(md)
PY

# 3) рендер и переименование
quarto render "$BUILD" --to typst
mv "${BUILD%.md}.pdf" REPORT.pdf
rm -f "$BUILD" "${BUILD%.md}.typ"
echo "Готово: REPORT.pdf"
