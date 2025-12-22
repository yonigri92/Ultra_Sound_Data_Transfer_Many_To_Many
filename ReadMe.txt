🏗 System Architecture
	The software is built on a modular UML architecture designed for high reliability in acoustic environments.

	Core Components
		Networking Layer (NetworkManager): Implements a custom CSMA/CA protocol with an RTS/CTS handshake to prevent acoustic data collisions in a 2-meter radius.

		Signal Processing Layer (SignalProcessor): Handles FSK (Frequency Shift Keying) modulation and FFT (Fast Fourier Transform) analysis to translate sound into 56-bit data frames.

		Collision Avoidance (CSMA_Manager): Uses unique prime-number-based waiting periods—RBWP (Regular Base Waiting Period) and MBWP (Minimal Base Waiting Period)—to manage network traffic and retries.

		Hardware Bridge (IAudioHardware): A cross-platform abstraction layer that standardizes audio buffers between Android (ANIAudioHardware) and iOS (IOSAudioHardware).

📡 Protocol Specification
	Frequency Range: 18,000 Hz – 20,000 Hz.

	Frame Size: 56 bits (8-bit Start Flag, 40-bit UserID payload, 8-bit CRC checksum).

	Range: Effective up to 2 meters.

	Collision Logic: Request-to-Send (RTS) / Clear-to-Send (CTS) handshake.

🛠 Prerequisites
	Android: AudioRecord API support.

	iOS: AVAudioEngine/AVAudioSession support.

	Hardware: High-frequency capable microphone and speaker (18kHz+ response).