import Foundation

// Muestras de HTML tal como lo emite Moodle 4.x por mod_quiz_get_attempt_data.

var failures = 0
func check(_ label: String, _ cond: Bool, _ detail: @autoclosure () -> String = "") {
    if cond { print("  ok  \(label)") }
    else { failures += 1; print("  FAIL \(label) \(detail())") }
}

func payload(_ html: String, type: String, slot: Int = 1) -> MoodleQuizQuestionPayload {
    let json = """
    {"slot":\(slot),"type":"\(type)","page":0,"html":\(jsonString(html)),
     "sequencecheck":1,"flagged":false,"state":"todo","maxmark":1.0,"number":\(slot)}
    """
    return try! JSONDecoder().decode(MoodleQuizQuestionPayload.self, from: Data(json.utf8))
}

func jsonString(_ s: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [s], options: [])
    var str = String(data: data, encoding: .utf8)!
    str.removeFirst(); str.removeLast()
    return str
}

// MARK: multichoice (opción simple)

let multichoiceHTML = """
<div id="question-3-1" class="que multichoice deferredfeedback notyetanswered">
  <div class="info"><h3 class="no">Pregunta <span class="qno">1</span></h3></div>
  <div class="content">
    <div class="formulation">
      <input type="hidden" name="q3:1_:sequencecheck" value="1">
      <div class="qtext"><p>¿Cuál es la capital de Francia?</p></div>
      <div class="ablock">
        <div class="answer">
          <div class="r0">
            <input type="radio" name="q3:1_answer" value="-1" id="q3:1_answer-1" checked="checked" class="sr-only">
            <input type="radio" name="q3:1_answer" value="0" id="q3:1_answer0">
            <div class="d-flex w-100"><label for="q3:1_answer0" class="ml-1 flex-fill">
              <span class="answernumber">a. </span>
              <div class="flex-fill ml-1"><div class="text_to_html">Par&iacute;s</div></div>
            </label></div>
          </div>
          <div class="r1">
            <input type="radio" name="q3:1_answer" value="1" id="q3:1_answer1">
            <div class="d-flex w-100"><label for="q3:1_answer1" class="ml-1 flex-fill">
              <span class="answernumber">b. </span>
              <div class="flex-fill ml-1"><div class="text_to_html">Londres</div></div>
            </label></div>
          </div>
        </div>
      </div>
      <input type="hidden" name="q3:1_:flagged" value="0">
    </div>
  </div>
</div>
"""

print("multichoice:")
let q1 = QuizQuestionParser.parse(payload(multichoiceHTML, type: "multichoice"))
check("texto", q1.text.contains("capital de Francia"), "→ '\(q1.text)'")
check("sequencecheck presente", q1.baseFields.contains { $0.name == "q3:1_:sequencecheck" })
check("flag detectado", q1.flagFieldName == "q3:1_:flagged", "→ \(q1.flagFieldName ?? "nil")")
if case .singleChoice(let field, let options) = q1.widget {
    check("campo", field == "q3:1_answer", "→ \(field)")
    // El radio "-1" es el placeholder de Moodle; se lista igual y la UI lo ignora.
    let real = options.filter { $0.value != "-1" }
    check("2 opciones reales", real.count == 2, "→ \(options.map(\.value))")
    check("entidad decodificada", real.first?.label == "París", "→ '\(real.first?.label ?? "")'")
    check("sin 'a. '", real.first?.label.hasPrefix("a.") == false)
    check("segunda opción", real.last?.label == "Londres", "→ '\(real.last?.label ?? "")'")
} else {
    failures += 1; print("  FAIL widget no es singleChoice → \(q1.widget)")
}

// MARK: multichoice múltiple (checkboxes)

let multiHTML = """
<div class="que multichoice">
  <div class="qtext"><p>Seleccioná los números pares</p></div>
  <input type="hidden" name="q7:2_:sequencecheck" value="3">
  <div class="answer">
    <div class="r0">
      <input type="hidden" name="q7:2_choice0" value="0">
      <input type="checkbox" name="q7:2_choice0" value="1" id="q7:2_choice0">
      <label for="q7:2_choice0"><span class="answernumber">a. </span>Dos</label>
    </div>
    <div class="r1">
      <input type="hidden" name="q7:2_choice1" value="0">
      <input type="checkbox" name="q7:2_choice1" value="1" id="q7:2_choice1">
      <label for="q7:2_choice1"><span class="answernumber">b. </span>Tres</label>
    </div>
  </div>
</div>
"""

print("multichoice múltiple:")
let q2 = QuizQuestionParser.parse(payload(multiHTML, type: "multichoice", slot: 2))
if case .multiChoice(let options) = q2.widget {
    check("2 casillas", options.count == 2, "→ \(options.count)")
    check("nombres por opción", options.map(\.fieldName) == ["q7:2_choice0", "q7:2_choice1"])
    check("etiquetas", options.map(\.label) == ["Dos", "Tres"], "→ \(options.map(\.label))")
    check("default 0 en ocultos", q2.baseFields.contains { $0.name == "q7:2_choice0" && $0.value == "0" })
} else {
    failures += 1; print("  FAIL widget no es multiChoice → \(q2.widget)")
}

// MARK: shortanswer

let shortHTML = """
<div class="que shortanswer">
  <div class="qtext"><p>Capital de Nicaragua</p></div>
  <input type="hidden" name="q9:3_:sequencecheck" value="1">
  <span class="answer"><input type="text" name="q9:3_answer" value="" size="30" placeholder="Respuesta"></span>
</div>
"""
print("shortanswer:")
let q3 = QuizQuestionParser.parse(payload(shortHTML, type: "shortanswer", slot: 3))
if case .shortText(let field, let ph) = q3.widget {
    check("campo", field == "q9:3_answer", "→ \(field)")
    check("placeholder", ph == "Respuesta")
} else {
    failures += 1; print("  FAIL widget no es shortText → \(q3.widget)")
}

// MARK: essay

let essayHTML = """
<div class="que essay">
  <div class="qtext"><p>Explicá la fotos&iacute;ntesis</p></div>
  <input type="hidden" name="q11:4_:sequencecheck" value="1">
  <input type="hidden" name="q11:4_answerformat" value="1">
  <textarea name="q11:4_answer" rows="10"></textarea>
</div>
"""
print("essay:")
let q4 = QuizQuestionParser.parse(payload(essayHTML, type: "essay", slot: 4))
check("texto con entidad", q4.text.contains("fotosíntesis"), "→ '\(q4.text)'")
if case .essay(let field, let fmtField, let fmt) = q4.widget {
    check("campo", field == "q11:4_answer", "→ \(field)")
    check("campo de formato", fmtField == "q11:4_answerformat")
    check("formato HTML", fmt == "1")
} else {
    failures += 1; print("  FAIL widget no es essay → \(q4.widget)")
}

// MARK: match (selects en tabla)

let matchHTML = """
<div class="que match">
  <div class="qtext"><p>Emparejá país y capital</p></div>
  <input type="hidden" name="q13:5_:sequencecheck" value="1">
  <table class="answer"><tbody>
    <tr class="r0"><td class="text">Francia</td><td class="control">
      <select name="q13:5_sub0"><option value="0">Elegir...</option><option value="1">París</option><option value="2">Roma</option></select>
    </td></tr>
    <tr class="r1"><td class="text">Italia</td><td class="control">
      <select name="q13:5_sub1"><option value="0">Elegir...</option><option value="1">París</option><option value="2">Roma</option></select>
    </td></tr>
  </tbody></table>
</div>
"""
print("match:")
let q5 = QuizQuestionParser.parse(payload(matchHTML, type: "match", slot: 5))
if case .selects(let items) = q5.widget {
    check("2 menús", items.count == 2, "→ \(items.count)")
    check("prompts", items.map(\.prompt) == ["Francia", "Italia"], "→ \(items.map(\.prompt))")
    check("campos", items.map(\.field) == ["q13:5_sub0", "q13:5_sub1"])
    check("3 opciones c/u", items.first?.options.count == 3)
} else {
    failures += 1; print("  FAIL widget no es selects → \(q5.widget)")
}

// MARK: tipo no soportado

let ddHTML = """
<div class="que ddwtos">
  <div class="qtext"><p>Arrastrá las palabras</p></div>
  <input type="hidden" name="q15:6_:sequencecheck" value="1">
  <input type="hidden" name="q15:6_p1" value="">
</div>
"""
print("ddwtos (no soportado):")
let q6 = QuizQuestionParser.parse(payload(ddHTML, type: "ddwtos", slot: 6))
if case .unsupported(let reason) = q6.widget {
    check("marcado no soportado", !reason.isEmpty)
    check("no responsable", q6.isAnswerable == false)
    check("igual conserva ocultos", q6.baseFields.count == 2, "→ \(q6.baseFields.count)")
} else {
    failures += 1; print("  FAIL debería ser unsupported → \(q6.widget)")
}

// MARK: robustez del tokenizador

let nastyHTML = """
<div class="que truefalse">
  <script>var x = "<div class='que'>trampa</div>"; if (a > b) { alert("<input>"); }</script>
  <div class="qtext"><p>El agua hierve a 100&deg;C &amp; 1 atm</p></div>
  <input type="hidden" name="q17:7_:sequencecheck" value="2">
  <input type=radio name=q17:7_answer value=1 id=q17:7_answer1>
  <label for="q17:7_answer1">Verdadero</label>
  <input type='radio' name='q17:7_answer' value='0' id='q17:7_answer0'>
  <label for='q17:7_answer0'>Falso</label>
</div>
"""
print("tokenizador (script, comillas mixtas, sin comillas):")
let q7 = QuizQuestionParser.parse(payload(nastyHTML, type: "truefalse", slot: 7))
check("script ignorado", !q7.text.contains("trampa"), "→ '\(q7.text)'")
check("ampersand decodificado", q7.text.contains("&"), "→ '\(q7.text)'")
if case .singleChoice(let field, let options) = q7.widget {
    check("campo sin comillas", field == "q17:7_answer", "→ \(field)")
    check("2 opciones", options.count == 2, "→ \(options.map(\.label))")
    check("etiquetas", options.map(\.label) == ["Verdadero", "Falso"], "→ \(options.map(\.label))")
} else {
    failures += 1; print("  FAIL widget no es singleChoice → \(q7.widget)")
}

// MARK: armado del envío

print("hoja de respuestas:")
var sheet = QuizAnswerSheet()
sheet.set(slot: 1, field: "q3:1_answer", value: "0")
sheet.set(slot: 2, field: "q7:2_choice1", value: "1")
let fields = sheet.fields(for: [q1, q2])
let map = Dictionary(fields.map { ($0.name, $0.value) }, uniquingKeysWith: { _, b in b })
check("respuesta pisa el default", map["q3:1_answer"] == "0", "→ \(map["q3:1_answer"] ?? "nil")")
check("sequencecheck viaja", map["q3:1_:sequencecheck"] == "1")
check("casilla marcada = 1", map["q7:2_choice1"] == "1")
check("casilla sin marcar = 0", map["q7:2_choice0"] == "0", "→ \(map["q7:2_choice0"] ?? "nil")")
check("no se pierde el flag", map["q3:1_:flagged"] == "0")

print("")
if failures == 0 {
    print("TODO OK")
} else {
    print("\(failures) FALLOS")
    exit(1)
}
