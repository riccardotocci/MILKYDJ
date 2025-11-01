// MIDI Controller - Versione con la libreria "The MidiBus" (soluzione definitiva)

import themidibus.*;

class MidiController {
  Deck deckA, deckB;
  MixerCenterPanel center;
  FileBrowserPanel browser;

  MidiBus myBus;

  // MAPPATURA CC
  int CC_VOL_A = 4;
  int CC_VOL_B = 10;
  int CC_CROSS = 5;
  int CC_A_LOW  = 0;
  int CC_A_MID  = 1;
  int CC_A_HIGH = 2;
  int CC_A_FX   = 3;
  int CC_B_LOW  = 6;
  int CC_B_MID  = 7;
  int CC_B_HIGH = 8;
  int CC_B_FX   = 9;
  int CC_PHONES = 11;

  // MAPPATURA NOTE
  int NOTE_CUE_A  = 60;
  int NOTE_CUE_B  = 61;
  int NOTE_LOAD_A = 62;
  int NOTE_LOAD_B = 63;

  MidiController(Deck a, Deck b, MixerCenterPanel c, FileBrowserPanel f) {
    deckA = a;
    deckB = b;
    center = c;
    browser = f;

    MidiBus.list(); // Stampa la lista dei device MIDI in console

    // Connettiti al primo input e output MIDI disponibili
    // Il numero [0] potrebbe dover essere cambiato se hai più device
    // Controlla la lista stampata in console per trovare il numero giusto
    myBus = new MidiBus(this, 0, -1); // Input: 0, Output: nessuno
  }

  // Funzione chiamata da The MidiBus quando arriva un CC
  void controllerChange(int channel, int number, int value) {
    float v = constrain(value / 127.0, 0, 1);

    if (number == CC_VOL_A) center.setVolumeA(v);
    else if (number == CC_VOL_B) center.setVolumeB(v);
    else if (number == CC_CROSS) center.setCrossfader(v);
    else if (number == CC_A_LOW) center.setFilterA(0, v);
    else if (number == CC_A_MID) center.setFilterA(1, v);
    else if (number == CC_A_HIGH) center.setFilterA(2, v);
    else if (number == CC_A_FX) center.setFilterA(3, v);
    else if (number == CC_B_LOW) center.setFilterB(0, v);
    else if (number == CC_B_MID) center.setFilterB(1, v);
    else if (number == CC_B_HIGH) center.setFilterB(2, v);
    else if (number == CC_B_FX) center.setFilterB(3, v);
    else if (number == CC_PHONES) center.setHeadphonesVolume(v);
  }

  // Funzione chiamata da The MidiBus quando arriva una Nota ON
  void noteOn(int channel, int pitch, int velocity) {
    if (pitch == NOTE_CUE_A) center.setCueA(!center.isCueAOn());
    else if (pitch == NOTE_CUE_B) center.setCueB(!center.isCueBOn());
    else if (pitch == NOTE_LOAD_A && browser != null) browser.loadSelectedToDeck(deckA);
    else if (pitch == NOTE_LOAD_B && browser != null) browser.loadSelectedToDeck(deckB);
  }

  // Non ci serve, ma la libreria la richiede
  void noteOff(int channel, int pitch, int velocity) {}

  // Chiudi la connessione MIDI quando lo sketch si ferma
  void dispose() {
    if (myBus != null) {
      myBus.stop();
    }
  }
}
