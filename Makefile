build:
	faust -a puredata.cpp -o fvol-pd.cpp fvol.dsp
	g++ -DPD -Wall -g -shared -Dmydsp=fvol -o fvol~.pd_linux fvol-pd.cpp