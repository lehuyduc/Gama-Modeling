/***
* Name: M23
* Author: lehuy
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model M23

/* Insert your model definition here */

global {	
	//***************************		TIME VARIABLES
	float stepDuration <- 3600#s;
	int timeElapsed <- 0 update:  int(cycle * stepDuration);
	float currentMinute<-0.0 update: ((timeElapsed mod 3600#s))/60#s; //Mod with 60 minutes or 1 hour, then divided by one minute value to get the number of minutes
	float currentHour<-0.0 update:((timeElapsed mod 86400#s))/3600#s;
	int currentDay <- 0.0 update:((timeElapsed mod 31536000#s))/86400#s;
	list<string> days <- ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
	string currentWeekDay update: days[currentDay mod 7];
	
	// ENUMS for locations
	int NB_TYPE <- 9;
	string TP_HOME <- "Home";
	string TP_INDUSTRY <- "Industry";
	string TP_OFFICE <- "Office";
	string TP_SCHOOL <- "School";
	string TP_SHOP <- "Shop";
	string TP_SUPERMARKET <- "Supermarket";
	string TP_CAFE <- "Cafe";
	string TP_RESTAURANT <- "Restaurant";
	string TP_PARK <- "Park";
	list<string> BUILDING_TYPES <- [TP_HOME, TP_INDUSTRY, TP_OFFICE, TP_SCHOOL, TP_SHOP, TP_SUPERMARKET, TP_CAFE, TP_RESTAURANT, TP_PARK];
	
	
	
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
		
		//************** INIT THE BUILDING TYPES ********************/
		loop i from: 0 to: NB_TYPE - 1{
			building[i].buildingType <- BUILDING_TYPES[i];
		}
		
		building[NB_TYPE].buildingType <- TP_SCHOOL;
			
		loop i from:NB_TYPE+1 to: length(building)-1 {
			if flip(0.85) {
				building[i].buildingType <- TP_HOME;
			}
			else {
				building[i].buildingType <- one_of(BUILDING_TYPES);
			}						
		}		 
		
		
		/********************  INIT THE HUMAN AGENTS  *********************************/
		nbInfected <- 0;
		
		create human number: humanNumber {	
			myHouse <- one_of(building where (each.buildingType = TP_HOME));
			myWorkplace <- one_of(building where (each.buildingType != TP_HOME));	
			mySchool <- one_of(building where (each.buildingType = TP_SCHOOL));
			location <- myHouse.location;			
			
			gender <- one_of(["male","female"]);
			age <- rnd(70) + 1;			
													
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

	// Personal characteristics 	
	building myHouse;
	building myWorkplace;
	building mySchool;
	string gender;
	int age min: 0 max: 100;
	
	int startWork <- 7;
	int endWork <- 17;
	int startSchool <- 7;
	int endSchool <- 17;	
		
		
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
	
	reflex go_child when: age<=3 {
		// do nothing
	}
	
	reflex go_student when: age >3 and age<=22 {	
		bool isAtSchool <- first(building overlapping(self)) = mySchool;
		bool isAtHome <- first(building overlapping(self)) = myHouse;
		
		if (currentHour >= startSchool and currentHour <= endSchool) {
			if (!isAtSchool) {
				do gotoLocation(mySchool);
			}
		}
		else {
			if(!isAtHome) {
  				do gotoLocation(myHouse);  				
  			}
		}
	}
	
	reflex go_adult when: age>22 and age<=55 {
		
		bool isAtWork <- first(building overlapping(self)) = myWorkplace;
		bool isAtHome <- first(building overlapping(self)) = myHouse;
		
		if (currentHour >= startWork and currentHour <= endWork) {
			if (!isAtWork) {
				do gotoLocation(myWorkplace);
			}
		}
		else {
			if(!isAtHome) {
  				do gotoLocation(myHouse);			
  			}
		}
	}
	
	reflex goRetiree when: age > 55 {
		// do nothing
		if (currentHour <= endWork) {
			building targetLocation <- one_of(building);			
			do gotoLocation(targetLocation);
		}						
		else {
			do gotoLocation(myHouse);
		}
	}
	
	
	//**********************************	ACTIONS/REFLEX ABOUT PANDEMIC/MASK						*******************************//

		
	reflex infect_others when: isInfected = true {
		float prob <- myTransmissionProb;
		
		building myBuilding <- first(building overlapping(self));
		list<human> close_humans <- (human overlapping(myBuilding)) where(each.isSusceptible = true);
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
	string buildingType;
	bool isInfected <- false;
	float infectionLevel <- 0;
	int lastDay <- 0;
	
	aspect default {
		draw shape color: #gray border: #black;
	}	
}

//******************************************************

experiment Model2_3 until: (nbExposed = 0 and nbInfected = 0) {
	parameter "Number of people" var: humanNumber init: 1000 min:200 max:2000 step: 200;
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

