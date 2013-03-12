import std.stdio;
import std.conv;

enum
{
    shaSuccess = 0,
    shaNull,            /* Null pointer parameter */
    shaInputTooLong,    /* input data too long */
    shaStateError       /* called Input after Result */
}

immutable uint SHA1HashSize = 20;

/*
 *  This structure will hold context information for the SHA-1
 *  hashing operation
 */
struct SHA1
{
private:
   uint[SHA1HashSize/4] Intermediate_Hash; /* Message Digest  */

   uint Length_Low;            // Message length in bits
   uint Length_High;           // Message length in bits

   // Index into message block array
   short Message_Block_Index;
   ubyte[64] Message_Block;      /* 512-bit message blocks      */

   bool Computed;               /* Is the digest computed?         */
   bool Corrupted;             /* Is the message digest corrupted? */
   int err;

   uint SHA1CircularShift(int bits, uint word)
   {
      return (((word) << (bits)) | ((word) >> (32-(bits))));
   }


   void ProcessMessageBlock()
   {
      const uint K[] =    [ 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC, 0xCA62C1D6 ];
      int        t;                 /* Loop counter                */
      uint      temp;              /* Temporary word value        */
      uint[80] W;             /* Word sequence               */
      uint      A, B, C, D, E;     /* Word buffers                */

      /*
      *  Initialize the first 16 words in the array W
      */
      for(t = 0; t < 16; t++)
      {
         W[t] = Message_Block[t * 4] << 24;
         W[t] |= Message_Block[t * 4 + 1] << 16;
         W[t] |= Message_Block[t * 4 + 2] << 8;
         W[t] |= Message_Block[t * 4 + 3];
      }

      for(t = 16; t < 80; t++)
      {
         W[t] = SHA1CircularShift(1,W[t-3] ^ W[t-8] ^ W[t-14] ^ W[t-16]);
      }

      A = Intermediate_Hash[0];
      B = Intermediate_Hash[1];
      C = Intermediate_Hash[2];
      D = Intermediate_Hash[3];
      E = Intermediate_Hash[4];

      for(t = 0; t < 20; t++)
      {
         temp =  SHA1CircularShift(5,A) +
                ((B & C) | ((~B) & D)) + E + W[t] + K[0];
         E = D;
         D = C;
         C = SHA1CircularShift(30,B);

         B = A;
         A = temp;
      }

      for(t = 20; t < 40; t++)
      {
         temp = SHA1CircularShift(5,A) + (B ^ C ^ D) + E + W[t] + K[1];
         E = D;
         D = C;
         C = SHA1CircularShift(30,B);
         B = A;
         A = temp;
      }

      for(t = 40; t < 60; t++)
      {
         temp = SHA1CircularShift(5,A) +
               ((B & C) | (B & D) | (C & D)) + E + W[t] + K[2];
         E = D;
         D = C;
         C = SHA1CircularShift(30,B);
         B = A;
         A = temp;
      }

      for(t = 60; t < 80; t++)
      {
         temp = SHA1CircularShift(5,A) + (B ^ C ^ D) + E + W[t] + K[3];
         E = D;
         D = C;
         C = SHA1CircularShift(30,B);
         B = A;
         A = temp;
      }

      Intermediate_Hash[0] += A;
      Intermediate_Hash[1] += B;
      Intermediate_Hash[2] += C;
      Intermediate_Hash[3] += D;
      Intermediate_Hash[4] += E;

      Message_Block_Index = 0;
   }

   void PadMessage()
   {
      if (Message_Block_Index > 55)
      {
         Message_Block[Message_Block_Index++] = 0x80;
         while(Message_Block_Index < 64)
         {
            Message_Block[Message_Block_Index++] = 0;
         }

         ProcessMessageBlock();

         while(Message_Block_Index < 56)
         {
            Message_Block[Message_Block_Index++] = 0;
         }
      }
      else
      {
         Message_Block[Message_Block_Index++] = 0x80;
         while(Message_Block_Index < 56)
         {

            Message_Block[Message_Block_Index++] = 0;
         }
      }

      /*
      *  Store the message length as the last 8 octets
      */
      Message_Block[56] = cast(ubyte) (Length_High >> 24);
      Message_Block[57] = cast(ubyte) (Length_High >> 16);
      Message_Block[58] = cast(ubyte) (Length_High >> 8);
      Message_Block[59] = cast(ubyte) Length_High;
      Message_Block[60] = cast(ubyte) (Length_Low >> 24);
      Message_Block[61] = cast(ubyte) (Length_Low >> 16);
      Message_Block[62] = cast(ubyte) (Length_Low >> 8);
      Message_Block[63] = cast(ubyte) Length_Low;

      ProcessMessageBlock();
   }

public:

   this(int dummy = 0) { reset(); dummy++; }

   @property error() { return err; }

   void reset()
   {
      Length_Low = 0;
      Length_High = 0;
      Message_Block_Index = 0;

      Intermediate_Hash = [ 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0 ];
      Computed = false;
      Corrupted = false;
   }

   ubyte[] result()
   {
      if (Corrupted)
         return null;

      ubyte[] rv;
      rv.length = SHA1HashSize;

      if (!Computed)
      {
         PadMessage();
         Message_Block[] = 0;
         Length_Low = 0;    /* and clear length */
         Length_High = 0;
         Computed = true;
      }

      for (int i = 0; i < SHA1HashSize; i++)
      {
         rv[i] = cast(ubyte)  (Intermediate_Hash[i>>2] >> 8 * ( 3 - ( i & 0x03 )));
      }

      return rv;
   }

   bool input(const(ubyte)* message_array, uint length)
   {
      if (!length)
         return true;

      if (message_array is null)
      {
         err = shaNull;
         return false;
      }

      if (Computed)
      {
        err = shaStateError;
        Corrupted = true;
        return false;
      }

      if (Corrupted)
         return false;

      while(length-- && !Corrupted)
      {
         Message_Block[Message_Block_Index++] = (*message_array & 0xFF);

         Length_Low += 8;
         if (Length_Low == 0)      // wrapped round
         {
            Length_High++;
            if (Length_High == 0) // wrapped round
            {
               // Message is too long
               Corrupted = true;
               err = shaInputTooLong;
               return false;
            }
         }

         if (Message_Block_Index == 64)
            ProcessMessageBlock();

         message_array++;
      }
      return true;
   }
}

