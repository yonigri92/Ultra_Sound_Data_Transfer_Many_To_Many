/*
pay attention!: when we send packages length will be the number of packages so 3 for example
when we recive packages EOR will be 2! as we start to count from 0! 


*/

//get and set are build in, this class will only hold the massage
//Unit to ensure scaleability and not meddle in integration responsibilities
import 'dart:typed_data';

import 'package:ultrasonic_transfer_app/Models/packet_builder_logic.dart';

  class DataFrameBuilderLogic{
    /*
    seq Byte- increasing number from 0 to 255 indicate the number of packet
        last packet is allways EOR packet so we have maximum of 254 packets per message
        each message is List of packets
        total length = payload.length/5 +1 last message
        total packets = total length as each int is a packet
    */
      int length = 1 ;
      final List<PacketBuilderLogic?> messages = List<PacketBuilderLogic?>.filled(256, null);
      static final divider = 0x07;
      DataFrameBuilderLogic(this.length);

    factory DataFrameBuilderLogic.fromPacket(Uint8List data) {
          /* creates Message From Data 
            takes Data and transformes it into packages with crc at the end.
            packages will return in array of ints each one of Size 8 bits ready to be sent
            Max capacity: 1270 bytes (254 data packets + 1 EOR).
            Packet structure: [0:0xAB][1:Seq][2-6:Data][7:CRC8].
            input: an array of ints each index is a byte
            Logic: 
                  1. take data and send it in Lists of Size 5 each time with cnt++(will be used for seq number)
                  2. add packet to the next int arr location 
                  3. continue loop  until we finish message 
                  4. add ending packet [Seq: cnt] [0xFF] [0xFF] [0xFF] [0xFF] [0xFF] [0xFF] [CRC]
                  4.2 EOR Packet: Always the last packet, Seq = total number of data packets (cnt).
            output: an array of int each index is 8 bits
          */
          if (data.length > 1270) {
              throw Exception("Data too large: Maximum 1270 bytes allowed per message (254 packets + EOR)");
          }
          int cnt = 0;// will be used duting payload to get seq number, after we get last seq will be length
          bool endOfMessageFlag = false;
          List<PacketBuilderLogic> newPacket = [];
          while (endOfMessageFlag == false){
          //the bigger question here is: why do we need seq we can just use the index to know what seq it is
          //but we do need it the reason is for when we recive data we want to be able to ask for the same seq again
          int start = cnt * 5;
          int end = (start + 5 > data.length) ? data.length : start + 5;
          newPacket.add (PacketBuilderLogic.createPacket(Uint8List.fromList([cnt]),data.sublist(start,end)));  
          cnt++;
          if(data.length<=cnt*5) endOfMessageFlag = true;
          }
          Uint8List lastSeq = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
          newPacket.add (PacketBuilderLogic.createPacket(Uint8List.fromList([cnt]),lastSeq));  
          DataFrameBuilderLogic newMessage = DataFrameBuilderLogic(newPacket.length);
          for (int i = 0 ; i <newPacket.length ;i ++){
            newMessage.messages[i] = newPacket[i];
          }
        return newMessage;

    } 
    bool reciveDataFrameBuilderLogic(Uint8List newData){
      /*
      this Method will recive Packet of a message will understand if it not corrupted
      and if its fine will throw the 10101011, will throw Seq(its saved allready), 
      throw CRC and save the 5 data bits inside correnct message
      input: packet
      output: true if data was recived correctly false otherwise
      */
     try{

        PacketBuilderLogic newPacket = PacketBuilderLogic.fromPacket(newData);
        if(messages[newPacket.seq] != null)   return false;//Allready recived this data packet
        if(length < newPacket.seq) length = newPacket.seq;
        Uint8List cleanData = newPacket.packet.sublist(2, 7);
        messages[newPacket.seq] = PacketBuilderLogic(newPacket.seq, cleanData);
     }
      catch(e){ return false;}
     return true; 
    }

    Uint8List reconstruct() {
      final BytesBuilder builder = BytesBuilder();
      for (int i = 0; i < length; i++) {
      if (messages[i] == null) {
      throw Exception("Missing packet at sequence $i. Message incomplete.");
      }
      builder.add(messages[i]!.packet);
      }
      return builder.takeBytes();
    }
}
