#include<UserButton.h>
#include "MoteToMote.h"
#include "printf.h"
#include<string.h>

module HeedC
{
	uses // genearl intefaces
	{
		interface Boot;
		interface Leds;
		interface Timer<TMilli> as TimerRepeatFunction;
		interface Timer<TMilli> as TimerFinalFunction;
		interface Timer<TMilli> as TimerInitFunction;
		interface Timer<TMilli> as TimerMeasurementFunction;
		interface Read<uint16_t> as Temp;
	}
	
	uses// button interfaces
	{
		interface Get<button_state_t>;
		interface Notify<button_state_t>;
	}
	
	
	uses //comunication interface
	{
		interface Packet;
		interface AMPacket;
		interface AMSend;
		interface SplitControl as AMControl;
		interface Receive;
	}

	uses 
	{
		interface Init;
	  	interface ParameterInit<uint16_t> as SeedInit;
	  	interface Random;
	}
	
	
	uses //VoltageC interface
	{
  		interface Read<uint16_t>;
	}
}

/*-------------------------------------------------------------------------------------*/
/*                                                                                     */
/*-------------------------------------------------------------------------------------*/
implementation
{

	static const int C_PROB= 5;
	static const float VOLTAGE = 1.5;
	static const float P_max = 0.01;

	//global variables
	bool radioBusy = FALSE;
	message_t pkt;
	
	//Heed Variables
	uint8_t heedLevel = 0;
	int CHprob;
	bool IsFinalCH = FALSE;
	bool InitFlag = FALSE;
	uint16_t neighbors[10];
	uint16_t neighborsBatteryLvl[10];
	uint16_t SCH[10];
	uint16_t SCHBatteryLvl[10];
	uint16_t SCHFinal[10];
	uint16_t SCHFinalBatteryLvl[10];
	uint16_t Cluster[10];
	uint16_t ClusterBatteryLvl[10];
	float batteryLvl = 0;
	uint8_t myCH = 0;
	bool isEmpty = TRUE;
	int CHprevious = 0;
	uint8_t batteryArgument = 0;
  	uint32_t t;
	uint16_t incrementalNonce = 0;
	
	// Heed prototypes
	void sendMsg(int recipient,char MsgId,uint16_t NodeId,uint8_t Level, uint8_t BatteryLvl, uint32_t Timestamp, uint16_t Measurement);
	void receiveLevelMsg(Mote_Msg * pkt);
	void Init();
	void Repeat();
	void Finalize();
	void receiveTentativeMsg(Mote_Msg * pkt);
	void RepeatAfterBatteryRead();
	void receiveFinalMsg(Mote_Msg * pkt);
	void receiveJoinClusterMsg(Mote_Msg * pkt);
	void receiveNewClusterHeadMsg(Mote_Msg * pkt);
	void receiveNewClusterHeadElectionMsg(Mote_Msg * pkt);
	void receiveMeasurementMsg(Mote_Msg * pkt);
	void displayLeds(uint8_t _idNodo);

/*-------------------------------------------------------------------------------------*/
/*                                     EVENTS                                          */
/*-------------------------------------------------------------------------------------*/



	event void Boot.booted() //Event fired as the mote is booted
	{
		int i;
		call Notify.enable(); //it is necessary for the button
		call AMControl.start(); //it is necessary for the radio
		
		// BaseStation
		if(TOS_NODE_ID == 1)
		{
			heedLevel = 1;
		}
		
		for(i = 0; i < 10; i++) 
		{
			neighbors[i] = 0;
			SCH[i] = 0;
			SCHFinal[i] = 0;
			Cluster[i] = 0;
		}
		//Initial read of the battery
		batteryArgument = 0;
		call Read.read();
	}
	
	// white button pressed
	event void Notify.notify(button_state_t val)
	{
		if(val == BUTTON_RELEASED)
		{
			
		}
	}
	
	event void AMSend.sendDone(message_t *msg,error_t err)
	{
		if(msg == &pkt)
		{
			radioBusy = FALSE;
		}
	}
	
	event void AMControl.startDone(error_t err)
	{
		if(err != SUCCESS)
		{
			call AMControl.start();
		}
	}
	
	event void AMControl.stopDone(error_t err)
	{		
	}
	

	//Message received event
	event message_t * Receive.receive(message_t *msg,void *payload,uint8_t len)
	{
		if(len == sizeof(Mote_Msg))
		{
			Mote_Msg * incomingPkt = (Mote_Msg*) payload;
			char msgId = incomingPkt->MsgId;

			/* We have used letters to switch between different kinds of messages
			 	-l is used for Level Message
			 	-t is used for Tentative CH message
			 	-f is used for Final CH message
			 	-j is used for Join Cluster message
			 	-c is used when a new CH is selected
			 	-n is used by a new CH to inform that he is the new CH
			 	-m is used for Measurements
			*/
			if(msgId == 'l' && incomingPkt->NodeId != TOS_NODE_ID)
			{
				receiveLevelMsg(incomingPkt);
			}
			else if(msgId == 't')
			{
				receiveTentativeMsg(incomingPkt);
			}	
			else if(msgId == 'f')
			{
				receiveFinalMsg(incomingPkt);
			}
			else if(msgId == 'j')
			{
				receiveJoinClusterMsg(incomingPkt);
			}
			else if(msgId == 'c')
			{
				receiveNewClusterHeadElectionMsg(incomingPkt);
			}
			else if(msgId == 'n')
			{
				receiveNewClusterHeadMsg(incomingPkt);
			}
			else if(msgId == 'm')
			{
				receiveMeasurementMsg(incomingPkt);
			}
		}
	
		return msg;
	}

	event void TimerFinalFunction.fired()
	{
		Finalize();
	}
	
	event void TimerInitFunction.fired()
	{
		Init();
	}

	event void TimerRepeatFunction.fired() 
	{
		Repeat();	
	}

	event void TimerMeasurementFunction.fired() 
	{
			batteryArgument = 2;
			call Read.read();
	}

	//Read battery event
	event void Read.readDone(error_t result, uint16_t val)
	{
		uint8_t maxBatteryLevelNB = 0;
		uint8_t indexMaxBatteryLevelNB = 0;
		int i = 0;

		if(result == SUCCESS) 
		{
			float v;
			v = (float)val/4095 * VOLTAGE;
			
			batteryLvl = v * 100;

			CHprob = (C_PROB*(C_PROB * v / VOLTAGE)-6.5)/0.2;
			
			if(CHprob < P_max) 
			{
				CHprob = P_max;
			}

			/*
				When batteryArgument is 1 the CH election will start
				when batteryArgument is 2:
					- if the battery is under 30% and a new CH is needed
					- if the node is not a CH read the temperature	
			*/

			if(batteryArgument == 1)
			{
				IsFinalCH = FALSE;  
				call TimerRepeatFunction.startPeriodic(2500);
			}	
			else if(batteryArgument == 2)
			{
				if(IsFinalCH)
				{
					if(batteryLvl <= 1.36) // 30%
					{
						for(i = 0; i < 10; i++) 
						{
							if(neighbors[i] != 0)
							{
								if(maxBatteryLevelNB < neighborsBatteryLvl[i])
								{
									indexMaxBatteryLevelNB = i;
									maxBatteryLevelNB = neighborsBatteryLvl[i];
								}
							}
							else break;
						}
					
						if(maxBatteryLevelNB > 1.36)
						{
							sendMsg(indexMaxBatteryLevelNB, 'c', TOS_NODE_ID, NULL, NULL, NULL, NULL);
							IsFinalCH = FALSE;
						}
					}
				}
				else // if a normal node (not CH) reads battery level
				{
					call Temp.read();
				}
			}	
		}
	}

	//Read the temperature
	event void Temp.readDone(error_t result, uint16_t data) 
  	{
		if(incrementalNonce >= 100)
		{
			incrementalNonce = 0;
		}
		incrementalNonce++;		
		sendMsg(myCH, 'm', TOS_NODE_ID, heedLevel, batteryLvl, incrementalNonce, data);
	}

/*-------------------------------------------------------------------------------------*/
/*                                     FUNCTIONS                                        */
/*-------------------------------------------------------------------------------------*/

	void sendMsg(int recipient, char MsgId,uint16_t NodeId,uint8_t Level, uint8_t BatteryLvl, uint32_t Timestamp, uint16_t Measurement)
	{
		int R = AM_BROADCAST_ADDR;

		if(radioBusy == FALSE)
		{
			// Creo il pacchetto da inviare
			Mote_Msg* msg = call Packet.getPayload(&pkt,sizeof(Mote_Msg));
			
			if(&MsgId != NULL)
			{
				msg->MsgId = MsgId;
			}
			if(&NodeId != NULL)
			{
				msg->NodeId = NodeId;
			}
			if(&Level != NULL)
			{
				msg->Level = Level;
			}
			if(&BatteryLvl != NULL)
			{
				msg -> BatteryLvl = BatteryLvl;
			}
			if(&Timestamp != NULL)
			{
				msg -> Timestamp = Timestamp;
			}
			if(&Measurement != NULL)
			{
				msg -> Measurement = Measurement;
			}
			// Invio il pacchetto
			if(recipient != NULL)
			{
				R = recipient;
			}
			if(call AMSend.send(R,&pkt,sizeof(Mote_Msg)) == SUCCESS)
			{
				radioBusy = TRUE;
			}
		}
	}

	void Init()
	{
		batteryArgument = 1;
		call Read.read();
	}

	void Repeat()
	{
		int i, r;
		int max;
		int maxIndex = 0;

		max = 0;
		
		if(SCH[0] != 0)
		{
			isEmpty = FALSE;
		}
		
		t=call TimerRepeatFunction.getNow();
		call SeedInit.init(t);
		r = call Random.rand16();
		r = r % 101;

		if(r < 0) 
		{
			r = r * -1;
		}
		
		if(!isEmpty) 
		{
			for(i = 0; i < 10; i++) 
			{
				if(SCHBatteryLvl[i] > max)
				{
					max = SCHBatteryLvl[i];
					maxIndex = i;
				}
			}

			myCH = SCH[maxIndex];
			
			if(myCH == TOS_NODE_ID)
			{
				if(CHprob == 100)
				{
					sendMsg(NULL,'f',TOS_NODE_ID, NULL, (uint8_t)batteryLvl, NULL, NULL);
					IsFinalCH = TRUE;
				}
				else 
				{
					sendMsg(NULL,'t',TOS_NODE_ID, NULL, (uint8_t)batteryLvl, NULL, NULL);
					
					for(i = 0; i < 10; i++) 
					{
						if(SCH[i] == TOS_NODE_ID)
						{
							break;
						}
						else if(SCH[i] == 0)
						{
							SCH[i] = TOS_NODE_ID;
							SCHBatteryLvl[i] = batteryLvl;
							break;
						}
					}
					
				}
			}
			
		} 
		else if(CHprob == 100)
		{
			sendMsg(NULL,'f',TOS_NODE_ID, NULL, (uint8_t)batteryLvl, NULL, NULL);
			IsFinalCH = TRUE;
		}
		else if(r <= CHprob)
		{
			sendMsg(NULL,'t',TOS_NODE_ID, NULL, (uint8_t)batteryLvl, NULL, NULL);
			
			for(i = 0; i < 10; i++) 
			{
				if(SCH[i] == TOS_NODE_ID)
				{
					break;
				}
				else if(SCH[i] == 0)
				{
					SCH[i] = TOS_NODE_ID;
					SCHBatteryLvl[i] = batteryLvl;
					break;
				}
			}
		}

		CHprevious = CHprob;
	
		CHprob = CHprob * 2;
		if(CHprob > 100)
		{
			CHprob = 100;
		}

		if(CHprevious == 100)
		{
			call TimerRepeatFunction.stop();
			call TimerFinalFunction.startOneShot(5000);		
		}
	}

	void Finalize()
	{
		int i;
		int max = 0;
		int maxIndex = 0;
		int myCHid;

		if(IsFinalCH == FALSE)
		{
			if(SCHFinal[0] != 0) //(SCH != empty)
			{
				for(i = 0; i < 10; i++) 
				{
					if(SCHFinalBatteryLvl[i] > max)
					{
						max = SCHFinalBatteryLvl[i];
						maxIndex = i;
					}
				}

				myCH = SCHFinal[maxIndex];
				if(SCHFinal[maxIndex] != TOS_NODE_ID)
				{
					sendMsg(SCHFinal[maxIndex],'j',TOS_NODE_ID, NULL, (uint8_t)batteryLvl, NULL, NULL);
					myCHid = SCHFinal[maxIndex];
				}
			} 
			else 
			{
				sendMsg(NULL,'f',TOS_NODE_ID, NULL, (uint8_t)batteryLvl, NULL, NULL);
			}
		} 	
		else 
		{
			sendMsg(NULL,'f',TOS_NODE_ID, NULL, (uint8_t)batteryLvl, NULL, NULL);
		}
			
		call TimerMeasurementFunction.startPeriodic(5000);
		displayLeds(myCHid);
	}

	void receiveLevelMsg(Mote_Msg * pkt)
	{
		uint16_t lvl = pkt->Level;
		uint8_t id = pkt->NodeId;
		uint8_t batteryLvlR = pkt -> BatteryLvl;

		if(id != TOS_NODE_ID)
		{
			//setting neighbours
			int i = 0;
			for(i = 0; i < 10; i++) 
			{
				if(neighbors[i] == id) 
				{
					break;
				}
				else if(neighbors[i] == 0)
				{
					neighbors[i] = id;
					neighborsBatteryLvl[i] = batteryLvlR;
					break;	
				}
			}

			if(heedLevel == 0 || (heedLevel != 0 && heedLevel > lvl+1))
			{
				heedLevel = lvl+1;
				sendMsg(NULL, 'l', TOS_NODE_ID, heedLevel, batteryLvl, NULL, NULL); 
				if(!InitFlag)
				{
					InitFlag = TRUE;
					call TimerInitFunction.startOneShot(3000);		
				}				

			}
		}
	}

	void receiveMeasurementMsg(Mote_Msg * pkt) 
	{
		uint16_t lvl = pkt->Level;
		uint8_t batteryLvl = pkt->BatteryLvl;
		uint8_t id = pkt->NodeId;
		uint32_t t = pkt->Timestamp;
		uint16_t data = pkt->Measurement;
		
 		int i;

		if(IsFinalCH)
		{
			if(batteryLvl != NULL)
			{
				for(i = 0; i < 10; i++)
				{
					if(neighbors[i] == id)
					{
						neighborsBatteryLvl[i] = batteryLvl;
						break;
					}
				}
				sendMsg(NULL, 'm', id, heedLevel, NULL, t, data);
			}
			else 
			{
				if(lvl > heedLevel)
				{
					sendMsg(NULL, 'm', id, heedLevel, NULL, t, data);
				}
			}
		}
		
	}

	void receiveNewClusterHeadElectionMsg(Mote_Msg * pkt) 
	{
		IsFinalCH = TRUE;		
		sendMsg(NULL, 'n', TOS_NODE_ID, NULL, NULL, NULL, NULL);
	}

	void receiveNewClusterHeadMsg(Mote_Msg * pkt) 
	{
		uint8_t id = pkt->NodeId;
		myCH = id;
	}

	void receiveTentativeMsg(Mote_Msg * pkt) 
	{
		uint8_t id = pkt->NodeId;
		uint8_t batteryLvl = pkt->BatteryLvl;
		int i;
		
		for(i = 0; i < 10; i++) 
		{
			if(SCH[i] == id)
			{
				break;
			}
			else if(SCH[i] == 0)
			{
				SCH[i] = id;
				SCHBatteryLvl[i] = batteryLvl;
				break;
			}
		}
		
	}

	void receiveFinalMsg(Mote_Msg * pkt) 
	{	
		uint8_t id = pkt->NodeId;
		uint8_t batteryLvl = pkt->BatteryLvl;
		int i;
		
		for(i = 0; i < 10; i++) 
		{
			if(SCHFinal[i] == id)
			{
				break;
			}
			else if(SCHFinal[i] == 0)
			{
				SCHFinal[i] = id;
				SCHFinalBatteryLvl[i] = batteryLvl;
				break;
			}
		}

	}

	void receiveJoinClusterMsg(Mote_Msg * pkt)
	{	
		uint8_t id = pkt->NodeId;
		uint8_t batteryLvl = pkt->BatteryLvl;
		int i;
		
		for(i = 0; i < 10; i++) 
		{
			if(Cluster[i] == 0)
			{
				Cluster[i] = id;
				ClusterBatteryLvl[i] = batteryLvl;
				break;
			}
		}


	}

	void displayLeds(uint8_t _idNodo)
	{
		int l;
		l = _idNodo % 8;

			if(l==0)
			{
				call Leds.led0Off();
				call Leds.led1Off();
				call Leds.led2Off();	
			}
			if(l==1)
			{
				call Leds.led0Off();
				call Leds.led1Off();
				call Leds.led2On();	
			}
			if(l==2)
			{
				call Leds.led0Off();
				call Leds.led1On();
				call Leds.led2Off();	
			}
			if(l==3)
			{
				call Leds.led0Off();
				call Leds.led1On();
				call Leds.led2On();	
			}
			if(l==4)
			{
				call Leds.led0On();
				call Leds.led1Off();
				call Leds.led2Off();	
			}
			if(l==5)
			{
				call Leds.led0On();
				call Leds.led1Off();
				call Leds.led2On();	
			}
			if(l==6)
			{
				call Leds.led0On();
				call Leds.led1On();
				call Leds.led2Off();	
			}
			if(l==7)
			{
				call Leds.led0On();
				call Leds.led1On();
				call Leds.led2On();	
			}	
	}

}
