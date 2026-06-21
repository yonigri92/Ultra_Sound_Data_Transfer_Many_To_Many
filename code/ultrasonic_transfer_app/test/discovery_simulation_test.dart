import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:async/async.dart';
import 'dart:async';
import 'dart:typed_data';

// ייבוא המחלקות המקוריות של הפרויקט שלך
import 'package:ultrasonic_transfer_app/Models/dispatcher.dart';
import 'package:ultrasonic_transfer_app/Models/audio_transmitter_logic.dart';
import 'package:ultrasonic_transfer_app/Models/fsk_control_wrapper_logic.dart';
import 'package:ultrasonic_transfer_app/Models/control_dispatcher_wrapper_logic.dart';
import 'package:ultrasonic_transfer_app/Models/fsk_modulation_logic.dart';
import 'package:ultrasonic_transfer_app/Models/packet_builder_logic.dart';

// =====================================================================
// 1. Mock Audio Transmitter
// עוקף את הרמקול הפיזי של הפלאפון, וזורק את הפקטות לערוץ וירטואלי (Stream)
// =====================================================================
class MockAudioTransmitter extends AudioTransmitter {
  final StreamController<Uint8List> virtualAirChannel;

  MockAudioTransmitter(FskControlWrapperLogic mod, this.virtualAirChannel) : super(mod);

  @override
  Future<void> initEngine() async {
    print("🎙️ [MOCK] Audio Engine Initialized (Muted)");
  }

  @override
  Future<void> transmitFrame(Uint8List frame) async {
    // מרוקנים את המודולטור כדי לא להיתקע בלולאה אינסופית
    modulator.loadFrame(frame);
    while (!modulator.isFinished) {
      modulator.generateNextBuffer(2048);
    }
    
    print("🚀 [Node A Transmits]: $frame");
    // זורקים את הפקטה לאוויר הוירטואלי כדי שהטסט יוכל לתפוס אותה
    virtualAirChannel.add(frame);
  }

  @override
  Future<void> transmitControlTone() async {
    while (!modulator.isFinished) {
      modulator.generateNextBuffer(2048);
    }
    print("🔊 [Node A Transmits]: Control Tone (Discovery/Busy)");
  }
}

// =====================================================================
// 2. The Test Sequence
// =====================================================================
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Simulate Complete Network Discovery Protocol (Node A + Test Script as Node B)', () async {
    print("=== STARTING VIRTUAL PROTOCOL SIMULATION ===");

    // כדי שה-DeviceIdCreateLogic לא יקרוס בסביבת טסט ללא פלאפון אמיתי
    FlutterSecureStorage.setMockInitialValues({});

    // יצירת צינור האוויר הוירטואלי
    final airController = StreamController<Uint8List>.broadcast();
    final airQueue = StreamQueue<Uint8List>(airController.stream);

    // אתחול המערכת של Node A
    final modulator = FskModulationLogic();
    final txWrapper = FskControlWrapperLogic(modulator);
    final transmitter = MockAudioTransmitter(txWrapper, airController);
    final dispatcherA = Dispatcher(transmitter);
    final wrapperA = ControlDispatcherWrapper(dispatcherA, txWrapper, transmitter);

    // פונקציית עזר: סימולציה של "קליטה במיקרופון". מפרקת פקטה ל-Nibbles ודוחפת לדיספצ'ר.
    Future<void> feedPacketToNodeA(Uint8List packet) async {
      print("📡 [Node B Replies]:   $packet");
      for (int i = 0; i < packet.length; i++) {
        int byte = packet[i];
        int highNibble = (byte >> 4) & 0x0F;
        int lowNibble = byte & 0x0F;
        await dispatcherA.pushSymbol(highNibble, (_) {});
        await dispatcherA.pushSymbol(lowNibble, (_) {});
      }
      // נותנים ל-Event Loop של Dart רגע לעבד את הפקטה
      await Future.delayed(const Duration(milliseconds: 100)); 
    }

    // === שלב 1: התחלת הדיסקברי מ-Node A ===
    print("\n--- INITIATING DISCOVERY ---");
    wrapperA.startDiscoveryWorkflow();
    
    // ממתינים שהטיימר של ה-Wrapper (שנייה אחת של אוויר נקי) יעבור
    await Future.delayed(const Duration(seconds: 2));

    // === שלב 2: תפיסת שרשרת ההקמה וסימולציה של Node B מצטרף ===
    print("\n--- STAGE 2: CHAIN FORMATION ---");
    Uint8List stage2PacketA = await airQueue.next; // מחכים ש-A ישדר
    
    expect(stage2PacketA[0], 0x0E, reason: "Node A should transmit Stage 2 Preamble (0x0E)");
    int idA = stage2PacketA[1]; // שומרים את ה-ID האמיתי ש-A הגריל לעצמו
    int idB = 0xD7; // מזהה פיקטיבי ל-Node B (הטסט)

    // מרכיבים פקטת תגובה מ-Node B
    Uint8List stage2PacketB = Uint8List.fromList(stage2PacketA);
    stage2PacketB[2] = idB; // Node B מוסיף את עצמו לסלוט הבא
    stage2PacketB[7] = PacketBuilderLogic.crcCheckSum(stage2PacketB.sublist(0, 7)); // מתקנים CRC
    
    // "משדרים" את התגובה חזרה ל-A
    await feedPacketToNodeA(stage2PacketB);

    // === שלב 3: סימולציה של חזרת העלה (Leaf Return) ===
    print("\n--- STAGE 3: RETURN MECHANISM ---");
    // נניח ש-B סיים את 8 הניסיונות שלו והבין שהוא עלה. הוא שולח שלב 3:
    Uint8List stage3PacketB = Uint8List.fromList(stage2PacketB);
    stage3PacketB[0] = 0x0F; // Preamble לשלב 3
    stage3PacketB[6] = idA;  // ה-Target הוא אבא שלו (Node A)
    stage3PacketB[7] = PacketBuilderLogic.crcCheckSum(stage3PacketB.sublist(0, 7));

    await feedPacketToNodeA(stage3PacketB);

    // === שלב 4: פיזור והתכנסות (Final Distribution) ===
    print("\n--- STAGE 4: FINAL DISTRIBUTION ---");
    Uint8List stage4PacketA = await airQueue.next; // מחכים ש-A יוציא פקטת שלב 4
    expect(stage4PacketA[0], 0x0A, reason: "Node A should transmit Stage 4 Preamble (0x0A)");
    
    // Node B (אנחנו) קיבל את פקטת ההפצה. אנחנו מאפסים את ה-Mask שלנו (שעמד על 0x20 למשל)
    Uint8List stage4PacketB = Uint8List.fromList(stage4PacketA);
    stage4PacketB[6] = 0x00; // התכנסות מוחלטת
    stage4PacketB[7] = PacketBuilderLogic.crcCheckSum(stage4PacketB.sublist(0, 7));

    // משדרים את אישור ההתכנסות הסופי חזרה ל-A
    await feedPacketToNodeA(stage4PacketB);

    // === סיום ואימות (Assertions) ===
    await Future.delayed(const Duration(seconds: 1)); // נותנים ללוגיקה להתעדכן
    
    print("\n=== FINAL VERIFICATION ===");
    print("Node A's Internal Topology Map: ${dispatcherA.latestTopology}");
    
    // מוודאים ש-A רשם את B בהצלחה בטופולוגיה!
    expect(dispatcherA.latestTopology.contains(idB), isTrue, reason: "Node A should have recorded Node B (0xD7) in its topology map!");
    
    print("✅ TEST PASSED SUCCESSFULLY! The protocol works flawlessly.");
  });
}