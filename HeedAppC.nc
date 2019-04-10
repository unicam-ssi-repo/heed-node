/*#define NEW_PRINTF_SEMANTICS
#include "printf.h"*/
configuration HeedAppC
{
}
implementation
{
	components HeedC as App;
	components MainC;
	components LedsC;
	components new SensirionSht11C();

	App.Temp -> SensirionSht11C.Temperature;
	App.Boot -> MainC;
	App.Leds -> LedsC;
	
	components new TimerMilliC() as TimerR;
  components new TimerMilliC() as TimerF;
  components new TimerMilliC() as TimerI;
  components new TimerMilliC() as TimerM;
  components PrintfC;
  components SerialStartC; // importantissimo se no non funzia il printf
  App.TimerRepeatFunction -> TimerR;
	App.TimerFinalFunction -> TimerF;
	App.TimerInitFunction -> TimerI;
	App.TimerMeasurementFunction -> TimerM;

	components UserButtonC;
	App.Get -> UserButtonC;
	App.Notify -> UserButtonC;
	
	//radio comunication
	components ActiveMessageC;
	components new AMSenderC(AM_RADIO);
	components new AMReceiverC(AM_RADIO);
	
	App.Packet -> AMSenderC;
	App.AMPacket -> AMSenderC;
	App.AMSend -> AMSenderC;
	App.AMControl -> ActiveMessageC;
	App.Receive -> AMReceiverC;

	components RandomC;
	App.Init -> RandomC;
	App.SeedInit -> RandomC;
	App.Random -> RandomC;
	
  

	/*-------------------------------------------------------------------------------------*/
	/*                                     Battery                                          */
	/*-------------------------------------------------------------------------------------*/

	components new VoltageC();
	App.Read -> VoltageC;
	
}
