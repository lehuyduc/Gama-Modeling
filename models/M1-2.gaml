/***
* Name: M12
* Author: lehuy
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model M12

global {	
	//***************************		TIME VARIABLES
	float stepDuration <- 3600#s;
	int timeElapsed <- 0 update:  int(cycle * stepDuration);
	float currentMinute<-0.0 update: ((timeElapsed mod 3600#s))/60#s; //Mod with 60 minutes or 1 hour, then divided by one minute value to get the number of minutes
	float currentHour<-0.0 update:((timeElapsed mod 86400#s))/3600#s;
	int currentDay <- 0.0 update:((timeElapsed mod 31536000#s))/86400#s;
	list<string> days <- ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
	string currentWeekDay update: days[currentDay mod 7];
	
	
	//************************** Human Species Variables
	int nbSusceptible <- 0 min:0 max:10000;
	int nbExposed <- 0; 	
	int nbInfected <- 0;
	int nbRecovered <- 0;
	
	float averageR0 <- 0 update: (human sum_of(each.myR0)) / max(1, nbRecovered + nbInfected);
			
	int humanNumber;
	int initialInfected;
	bool contagionInTransport;
	float distanceContamination <- 3#m;
	float transmissionProb <- 0.17;	
	
	
	//--------- 	LOADING SHAPE FILES	
	graph roadNetwork;	
	map<road,float> roadWeights;
	file road_file <- file("../includes/clean_roads.shp");
	file building_file <- file("../includes/buildings.shp");			
	geometry shape <- envelope(envelope(road_file));
		
	init {		
		create road from: road_file;
		create building from: building_file;
		
		roadNetwork <- as_edge_graph(road);
		roadWeights <- road as_map (each::each.shape.perimeter);
		
		/********************  INIT THE HUMAN AGENTS  *********************************/
		nbInfected <- 0;
		
		create human number: humanNumber {											
			if nbInfected < initialInfected {
				do set_infected();
			}
		}
		
		nbRecovered <- 0;
		nbExposed <- 0;
		nbSusceptible <- humanNumber - nbInfected;
	}
	
	reflex stop_simulation when: nbExposed = 0 and nbInfected = 0 {		
		do pause;
	}
}

/* Insert your model definition here */
//Species host which represents the host of the disease
species human skills:[moving] {
	
	//Different booleans to know in which state is the host
	bool isSusceptible <- true;
	bool isExposed <- false;
	bool isInfected <- false;
	bool isRecovered <- false;
	bool isDead <- false;
	
	float myTransmissionProb <- transmissionProb;
	
	int exposedDay <- 0;
	int infectiousDay <- 0;
	int incubationTime <- rnd(7) + 3;
	int infectiousTime <- rnd(20) + 5; 
	float myR0 <- 0;
		
		
	//Color of the host
	rgb color <- #green;
	
	//******************	ACTION/REFLEX ABOUT GOING PLACES
	
	action gotoLocation(building targetPlace) {
		bool arrived <- first(building overlapping(self)) = targetPlace;
		
		if (!arrived) {
			if (contagionInTransport) {
				do goto target: any_location_in(targetPlace) on: roadNetwork speed: (rnd(100)+1)	#m/#s;
			}
			else {
				location <- any_location_in(targetPlace);
			}			
		}
	}
	
	reflex go_random {
		do gotoLocation(one_of(building));
	}
	
	//**********************************	ACTIONS/REFLEX ABOUT PANDEMIC/MASK						*******************************//

		
	reflex infect_others when: isInfected = true {
		float prob <- myTransmissionProb;
		
		list<human> close_humans <- (human at_distance(distanceContamination)) where(each.isSusceptible = true);
		loop man over: close_humans {
			if flip(prob) {			
				myR0 <- myR0 + 1;	
				ask man {
					do set_exposed();
				}
			}
		}		
	}
	
	action set_exposed {		
		isSusceptible <- false;
		isExposed <- true;
		isInfected <- false;
		isRecovered <- false;
		color <- #orange;
		nbSusceptible <- nbSusceptible - 1;
		nbExposed <- nbExposed + 1;
		exposedDay <- currentDay;
	}
	
	reflex become_infected when: isExposed=true and exposedDay + incubationTime < currentDay {
		do set_infected();
	}
	
	action set_infected {
		isSusceptible <- false;
		isExposed <- false;
		isInfected <- true;
		isRecovered <- false;
							
		color <- #red;
	
		infectiousDay <- currentDay;
		nbExposed <- nbExposed - 1;
		nbInfected <- nbInfected + 1;	
	}
	
	reflex become_recovered when: isInfected and infectiousDay + infectiousTime <currentDay {
		isSusceptible <- false;
		isExposed <- false;
		isInfected <- false;
		isRecovered <- true;
				
		color <- #blue;
		nbInfected <- nbInfected - 1;
		nbRecovered <- nbRecovered + 1;
	}
	
	aspect default {
		draw circle(1) color: color;
	}
}

species road {		
	float speed_rate <- 1.0;

	aspect default{
		draw shape width: 4#m-(3*speed_rate)#m color: #grey;
	}	
}

species building {			
	aspect default {
		draw shape color: #gray border: #black;
	}	
}

//******************************************************

experiment Model1_2 until: (nbExposed = 0 and nbInfected = 0) {
	parameter "Number of people" var: humanNumber init: 500 min:200 max:2000 step: 200;
	parameter "Initial infected" var: initialInfected init:10 min:1 max:100;
	
	
	output {
		display main {
			species road aspect: default;
			species building aspect: default;
			species human aspect: default;						
		}
		
		display Infected_count {
			chart "Human types" type: series style: line {
				datalist ["#Susceptible", "#Exposed", "#Infected", "#Recovered"] value: [nbSusceptible, nbExposed, nbInfected, nbRecovered] color: [#green, #orange, #red, #blue];
			}
		}
		
		display R0_chart {
			chart "R0 values" type: series style: line {
				datalist ["Min R0", "Max R0", "Average R0"] 
				value: [human where(each.isInfected or each.isRecovered) min_of(each.myR0), human where(each.isInfected) max_of(each.myR0), averageR0]
	       		color: [#green, #orange, #red, #teal, #blue];
			}
		}
		
		monitor "Susceptible" value: nbSusceptible;
		monitor "Exposed" value: nbExposed;
		monitor "Infected" value: nbInfected;
		monitor "Recovered" value: nbRecovered;
		monitor "Hour:" value: currentHour;
		monitor "Day:" value: currentDay;		
	}
	
}

