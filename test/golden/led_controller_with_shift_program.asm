# 9/25/26 Sara: his program, rewritten in verilog literals now that bare
# digits are an error. 'h20, not 'd20: in his original 20 meant 32 ms.
# the .mem beside this is unchanged, byte for byte, and has to stay so.
0:	LED_SET_LOW_BYTE  # set 0-7
#1:	01		  # one light on
1:	'h01		  # one light on
2:	LED_SET_HIGH_BYTE # set 8-16
#3:	00		  # no lights on
3:	'h00		  # no lights on
4:	LED_LEFT_SHIFT	  # rotate light
5:	SLEEP_MS 	  # pause
#6:	20     		  # 20ms
6:	'h20     		  # 20ms
7: 	JUMP   		  # loop back
#8:	04      	  # to left shift cmd
8:	'd4      	  # to left shift cmd
