//get and set are build in, this class will only hold the massage
//Unit to ensure scaleability and not meddle in integration responsibilities
class Message{
    final String payload;
    final String checksum;
  Message(this.payload,this.checksum);


  factory Message.fromBitStream(List<int> bitStream) {
  /* This is the checkSum, will only build Message object if CHECKSUM is correct if not will throw error
  input: the newest message recived all bitstream message+ checksum
  Logic: 
        1.split to payload and checksum
        2.run CheckSum
  output: if incorrect throw error
          return Message object if correct
  */
  //split the payload and checksum
  List<int> newpayload,newchecksum;
  newpayload = bitStream.sublist(0,bitStream.length - 8);
  newchecksum = bitStream.sublist(bitStream.length - 8,bitStream.length);
  //CRC CheckSum
  if(_crcCheckSum(newpayload,newchecksum)){


  }else{

  }
  }
  bool _crcCheckSum(List<int> payload,List<int> checksum){
      int crc;
      List<int> payload; 
      //get the first 8 bits and CheckSum
      for (int i = 0 ; i++ i <8){

      } 




  }
}
