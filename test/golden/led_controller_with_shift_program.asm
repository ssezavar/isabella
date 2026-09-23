0:	LED_SET_LOW_BYTE  # set 0-7
1:	01		  # one light on
2:	LED_SET_HIGH_BYTE # set 8-16
3:	00		  # no lights on
4:	LED_LEFT_SHIFT	  # rotate light
5:	SLEEP_MS 	  # pause
6:	20     		  # 20ms
7: 	JUMP   		  # loop back
8:	04      	  # to left shift cmd
