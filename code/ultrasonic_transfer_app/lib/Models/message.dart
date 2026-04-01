//get and set are build in, this class will only hold the massage
//Unit to ensure scaleability and not meddle in integration responsibilities

class Message{
    final List<int> payload;
    final List<int> checksum;
    static final divider = 0x07;
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

  if(_crcCheckSum(bitStream)){
      return Message(bitStream.sublist(0,bitStream.length - 8),bitStream.sublist(bitStream.length - 8,bitStream.length));
  }else{
    throw FormatException("CheckSum Incorrect");
  }
  }
  static bool _crcCheckSum(List<int> payload){
      //initialize CRC by placeing first 8 bits inside int
      int currentDivider = 0;
      
      // getting the first number(first 8 digits from bitstream)
      for(int i=0;i<8;i++){
        currentDivider += payload[i];
        if(i!=7) currentDivider = currentDivider<<1;//make sure we dont move left into 9 digits 
        
      } 
         currentDivider = currentDivider & 0xFF;
      for(int i = 8 ; i < payload.length; i ++){
        if((currentDivider&0x80)==0){// if the last bit is zero count how many 0 are ther and move to the 1 bit to the right
          currentDivider = currentDivider<<1;
          currentDivider = currentDivider | payload[i];
          currentDivider = currentDivider & 0xFF;
        }
        else{//divide the currentDivider by the checksum and 
            currentDivider = currentDivider<<1;
            currentDivider = currentDivider | payload[i];
            currentDivider = currentDivider^divider;
            currentDivider = currentDivider & 0xFF;
        }
      }
    return currentDivider == 0 ;
  }
}
