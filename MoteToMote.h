#ifndef MOTE_TO_MOTE_H
#define MOTE_TO_MOTE_H

typedef nx_struct Message
{
	nx_uint32_t MsgId;
	nx_uint16_t NodeId;
	nx_uint8_t Level;
	nx_uint8_t BatteryLvl;
	nx_uint32_t Timestamp;
	nx_uint16_t Measurement;
} Mote_Msg;

enum 
{
	AM_RADIO = 6
};

#endif 
