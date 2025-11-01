#!/bin/bash
# Script semplice: Workflow completo automatico (separa + analizza)

# Attiva ambiente
eval "$(conda shell.bash hook)"
conda activate stem_separator

# Verifica argomento
if [ $# -eq 0 ]; then
    echo "Uso: ./workflow_completo.sh file_audio.mp3"
    echo ""
    echo "Esempio:"
    echo "  ./workflow_completo.sh \"Mau P - BEATS FOR THE UNDERGROUND.mp3\""
    exit 1
fi

INPUT_FILE="$1"

# Verifica file esista
if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ File non trovato: $INPUT_FILE"
    exit 1
fi

# Estrai nome brano
SONG_NAME=$(basename "$INPUT_FILE" | sed 's/\.[^.]*$//')
STEMS_DIR="stems/${SONG_NAME}"

echo "🎵 Processing: $SONG_NAME"
echo "=================================="
echo ""

# Step 1: Separa stems
echo "📁 Step 1/2: Separazione stems..."
python ambisonics_automation.py separate "$INPUT_FILE"

if [ $? -ne 0 ]; then
    echo "❌ Errore nella separazione stems"
    exit 1
fi

echo ""
echo "✅ Stems creati in: $STEMS_DIR/"
echo ""

# Step 2: Analizza stems
echo "📊 Step 2/2: Analisi stems → JSON..."
python ambisonics_automation.py analyze --folder "$STEMS_DIR"

if [ $? -ne 0 ]; then
    echo "❌ Errore nell'analisi"
    exit 1
fi

echo ""
echo "=================================="
echo "✅ Workflow completato!"
echo "=================================="
echo ""
echo "📁 Stems: $STEMS_DIR/"
echo "   • vocals.wav"
echo "   • drums.wav"
echo "   • bass.wav"
echo "   • other.wav"
echo ""
echo "📄 Analisi JSON: output/"
ls -1 output/*_analysis.json | tail -4 | sed 's/^/   • /'
echo ""
echo "💡 Carica in SuperCollider:"
echo "   var data = \"output/vocals_analysis.json\".parseJSONFile;"
echo ""
