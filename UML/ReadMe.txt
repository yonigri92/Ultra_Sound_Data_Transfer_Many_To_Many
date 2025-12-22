Ultrasonic System: Final Class Diagram Documentation
Class: AcousticNode
The central controller for the background proximity service.

- userID: A unique 40-bit identifier assigned to the device to distinguish it during broadcasts.

- rbwpValue: The Regular Base Waiting Period (high prime number) used to cycle the 5-minute idle state.

- mbwpValue: The Minimal Base Waiting Period (low prime number) used for the backoff timer during collisions.

+ startService(): Initializes the background thread to begin listening for ultrasonic signals.

+ stopService(): Safely terminates audio recording and networking tasks to save battery.

Class: NetworkManager
Manages the RTS/CTS handshake and carrier sensing logic.

- isChannelBusy: A boolean flag updated by the SignalProcessor when energy is detected in the 18-20 kHz band.

- retryCount: Tracks the number of failed RTS attempts before forcing a longer wait period.

+ sendRTS(): Transmits a "Request to Send" signal to reserve the acoustic channel.

+ handleCTS(): Processes incoming "Clear to Send" responses before starting data transmission.

+ listenForCarrier(): Monitors the microphone input to ensure the channel is idle before talking.

Class: SignalProcessor
The mathematical engine for sound-to-data conversion.

- sampleRate: The frequency at which audio is captured (standard 44.1 kHz or 48 kHz).

- frequencies: The specific 18-20 kHz frequency bins used for FSK modulation.

+ applyFFT(): Performs a Fast Fourier Transform to convert raw audio buffers into frequency data for analysis.

+ generateFSKTone(): Converts binary data into specific ultrasonic frequencies for the speaker.

+ validateChecksum(): Compares the received 8-bit CRC against the data payload to ensure no corruption occurred.

Class: PlatformAudioBridge
The translation layer that normalizes audio data between different operating systems.

- targetSampleRate: The fixed sample rate (e.g., 44100 Hz) that the SignalProcessor expects for accurate FFT.

+ translateToAndroid(): Adapts high-level audio commands to work with Android-specific buffer sizes.

+ translateToIOS(): Adapts high-level audio commands to work with iOS-specific audio sessions.

+ normalizeBuffer(): Resamples or adjusts raw audio data from the hardware to ensure the 18-20 kHz signals are consistent across devices.

Class: IAudioHardware (Interface)
A template that ensures cross-platform compatibility between Android and iOS.

+ startRecording(): Standardized command to activate the device microphone.

+ startPlayOutput(): Standardized command to activate the device speaker.

+ getRawBuffer(): Returns a normalized audio buffer so the SignalProcessor works the same on any OS.

Class: ANIAudioHardware & IOSAudioHardware
OS-specific drivers that implement the IAudioHardware interface.

ANIAudioHardware: Uses Android AudioRecord and AudioTrack APIs to manage the hardware.

IOSAudioHardware: Uses Apple AVAudioEngine or AudioUnit to manage the hardware.

Class: Frame
Defines the 56-bit data packet structure.

- startFlag: A specific bit pattern that signals the beginning of a new data transmission.

- payload: The 40-bit segment containing the sender's UserID.

- checksum: An 8-bit error-detection code to verify message integrity.

+ serialize(): Converts the frame object into a raw byte array ready for the acoustic modem.

+ calculateCRC(): Generates the 8-bit checksum for error detection.

Class: CSMA_Manager
Dedicated class for managing collision avoidance timing.

- RBWP: Regular Base Waiting Period value.

- MBWP: Minimal Base Waiting Period value.





Final Description of Your Class Diagram
This diagram represents the structural blueprint of the ultrasonic communication system, organized into four primary layers:

1. System Lifecycle Layer (AcousticNode & CSMA_Manager)
AcousticNode: Acts as the main controller, holding the device's unique 40-bit UserID and managing the transition between background idle states and active networking.

CSMA_Manager: Specifically handles the timing intervals. It contains the RBWP (Regular Base Waiting Period) for standard 5-minute cycles and the MBWP (Minimal Base Waiting Period) for collision backoff.

2. Networking Layer (NetworkManager & Frame)
NetworkManager: Implements the CSMA/CA protocol. It coordinates the RTS/CTS handshake and monitors the isChannelBusy flag to prevent data collisions.

Frame: Defines the physical data structure of the 56-bit acoustic packet, including the start flag, the 40-bit payload (UserID), and the 8-bit checksum.

3. Processing Layer (SignalProcessor)
This class is the "brain" of the communication. It uses FFT (Fast Fourier Transform) to detect frequencies in the 18–20 kHz range and FSK (Frequency Shift Keying) to convert binary data into sound. It also performs the final Checksum validation to ensure data integrity.

4. Hardware Abstraction Layer (PlatformAudioBridge & IAudioHardware)
The Bridge Pattern: This solves your cross-platform requirement. The PlatformAudioBridge normalizes the sample rates between devices.

Interface Realization: Both ANIAudioHardware (Android) and IOSAudioHardware (iOS) implement the IAudioHardware interface. This allows the app to run the exact same networking logic regardless of whether it is using Android's AudioRecord or Apple's AVAudioEngine.