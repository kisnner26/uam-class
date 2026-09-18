#!/bin/bash
# Verifica el parser de preguntas contra HTML real de Moodle 4.x.
#
# El parser es la pieza más frágil de todo el módulo de exámenes: si Moodle
# cambia el markup de una pregunta, esto lo detecta antes que un examen real.
# Corrélo después de tocar HTMLTree.swift o QuizQuestionParser.swift.
set -e
cd "$(dirname "$0")/.."
S=Sources/UAMClass
OUT=$(mktemp -d)
xcrun swiftc -O -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -o "$OUT/ptest" \
  Tools/quiz-parser-check/main.swift \
  "$S/Utils/HTMLStripping.swift" \
  "$S/Services/HTMLTree.swift" \
  "$S/Services/QuizQuestionParser.swift" \
  "$S/Models/QuizModels.swift"
"$OUT/ptest"
