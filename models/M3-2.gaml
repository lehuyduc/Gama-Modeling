/***
* Name: M31
* Author: lehuy
* Description: 
* Tags: Tag1, Tag2, TagN
***/

model M31

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
	
	//***************************		Const enums for locations
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
	int nbSusceptible;
	int nbExposed <- 0; 	
	int nbInfected <- 0;
	int nbConfirmed <-0 ;
	int nbRecovered <- 0;
	
	float averageR0 <- 0 update: (human sum_of(each.myR0)) / max(1, nbRecovered + nbInfected);
			
	int humanNumber;
	int initialInfected;
	bool contagionInTransport;
	bool contagionInBuilding;
	float distanceContamination <- 3#m;
	float transmissionProb <- 0.17;	
	float asymptomProb <- 0.3;
	float asymptomReduction <- 0.45;
	
	
	//************************** Policies + LocalAuthority variables
	// ENUMS for policies
	string POLICY_BY_TIME <- "Apply policy by time";
	string POLICY_BY_INFECTED <- "Apply policy by infected";
	
	// A policy is applied if it's > 0. We use int instead of bool to allow multiple level of policy in the future
	int policyNoSchool <- 0;
	int policyWearMask <- 0;
	int policyContainByAge <- 0;
	int policyTotalLockdown <- 0;
	int policyFreeFood <- 0;
	
	bool requireMask <- false;
	bool requireContainByAge <- false;
	
	// Controlling when to apply policies, and how many tests can be done
	int timeToApply;
	int infectedToApply;
	int nbTestPerDay;
	float truePositiveRate <- 0.89;
	float trueNegativeRate <- 0.92;
	
	string policyTriggerMode;
	map<string, bool> isAllowed;	// isAllowed[TP_SCHOOL] means people can go to school				
		
	
	//************************** Load shape files
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
			if flip(0.8) {
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
		
		//************** INIT THE POLICIES ********************/
		// in the beginning, all locations are allowed. Some policies will disable some location
		loop i from: 0 to: NB_TYPE - 1 {
			isAllowed[BUILDING_TYPES[i]] <- true;
		}
		
		create LocalAuthority number: 1 {
			// we only need 1 LocalAuthority object. Since it only uses global variables, no initialization is needed	
		}
	}
	
	reflex stop_simulation when: nbExposed = 0 and nbInfected = 0 {		
		do pause;
	}
}

/* Insert your model definition here */
//Species host which represents the host of the disease
species human skills:[moving] {
	// variables to handle going to supermarket (allowed to go even in lockdown/containment)
	int lastBuyFoodDay <- 0;
	bool goingToSupermarket <- false;
	bool goingBackHome <- false;
	building targetSupermarket;
	
	//Different booleans to know in which state is the host
	bool isSusceptible <- true;
	bool isExposed <- false;
	bool isInfected <- false;
	bool isConfirmed <- false;
	bool isRecovered <- false;
	bool isDead <- false;
	
	bool asymptom;
	
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
	
	action teleportToLocation(building targetPlace) {
		location <- any_location_in(targetPlace);
	} 
		
	reflex go_child when: age<=3 {
		// do nothing
	}
	
	reflex go_student when: age >3 and age<=22 {	
		if (not isAllowed[TP_SCHOOL] or isConfirmed) {
			return;
		}
		
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
		if (not isAllowed[myWorkplace.buildingType] or isConfirmed) {
			return;
		}
		
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
		if requireContainByAge or isConfirmed {
			return;
		}
		if (currentHour <= endWork) {
			building targetLocation <- one_of(building);	
			if (not isAllowed[targetLocation.buildingType]) {
				return;
			}
					
			do gotoLocation(targetLocation);
		}						
		else {
			do gotoLocation(myHouse);
		}
	}
	
	reflex goBuyFood when: age > 10 and lastBuyFoodDay!=currentDay and (flip(0.3) or goingToSupermarket or goingBackHome) {
		if isConfirmed or policyFreeFood > 0
		   or (age>3 and age<=22 and currentHour>startSchool and currentHour<endSchool and isAllowed[TP_SCHOOL])
		   or (age>22 and age<=55 and currentHour>startWork and currentHour<endWork and isAllowed[myWorkplace.buildingType])
		{
			return;
		}
				
		
		if goingToSupermarket = false and goingBackHome = false {
			goingToSupermarket <- true;
			targetSupermarket <- one_of(building where(each.buildingType = TP_SUPERMARKET));
		}
		
		building currentBuilding <- first(building overlapping(self));
		if goingToSupermarket {
			do gotoLocation(targetSupermarket);
			
			if currentBuilding = targetSupermarket { // arrive at the supermarket and buy food successful
				//write("reached market");
				lastBuyFoodDay <- currentDay;
				goingToSupermarket <- false;
				goingBackHome <- true;
			}	
		}		
		
		if goingBackHome {
			//write("Going home");
			do gotoLocation(myHouse);
			
			if currentBuilding = myHouse {
				goingBackHome <- false;
			}
		}		
	}
	
	//**********************************	ACTIONS/REFLEX ABOUT PANDEMIC/MASK						*******************************//
	reflex exposed_from_environment {	
		if isSusceptible = false or contagionInBuilding = false{
			return;
		}
		
		building current_building <- first(building overlapping(self));
		if current_building = nil {
			return;
		}
		if (flip(current_building.infectionLevel)) {
			do set_exposed();
		}		 
	}
		
	reflex infect_others when: isInfected = true {
		float prob <- transmissionProb;
		if requireMask {
			prob <- prob * 0.5;
		}
		if asymptom {
			prob <- prob * asymptomReduction;
		}
		
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
		
		asymptom <- flip(asymptomProb);
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
	
	action startQuarantine {
		isConfirmed <- true;
	}
	
	action stopQuarantine {
		isConfirmed <- false;
		do teleportToLocation(myHouse);
	}
	
	//------------------
	
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
	
	reflex update_infection_level {
		if contagionInBuilding = false{
			return;
		}
		list<human> nearInfectedHumans <- (human overlapping(self))  where (each.isInfected);
		if (!requireMask) {
			infectionLevel <- infectionLevel + transmissionProb * 0.1 * length(nearInfectedHumans);	
		}
		else {
			infectionLevel <- infectionLevel + transmissionProb * 0.05 * length(nearInfectedHumans);
		}
		
		if (lastDay != currentDay) {
			infectionLevel <- max(0,infectionLevel*0.5 - 0.1);
			lastDay <- currentDay;
		}			
	}	
	
	aspect default {
		draw shape color: #gray border: #black;
	}	
}

species LocalAuthority {	
	int lastDay <- 0;
				
	bool shouldStartPolicy {
		//write("should we apply");
		if (policyTriggerMode = POLICY_BY_TIME) {
			if currentDay >= timeToApply {
				return true;
			}
			else {
				return false;
			}
		}
		
		if (policyTriggerMode = POLICY_BY_INFECTED) {
			if nbConfirmed >= infectedToApply {
				return true;
			}
			else {
				return false;
			}
		}
	}
		
	reflex applyPolicy when: shouldStartPolicy() {
		//write("applying policies");
		if policyNoSchool > 0 {
			isAllowed[TP_SCHOOL] <- false;
		}
		
		if policyTotalLockdown > 0 {
			loop i from:0 to: NB_TYPE - 1{
				isAllowed[BUILDING_TYPES[i]] <- false;
			}
		}
		
		isAllowed[TP_SUPERMARKET] <- true;
		//******************************
		if policyWearMask > 0 {
			requireMask <- true;
		}		
		
		if policyContainByAge > 0 {
			requireContainByAge <- true;
		}
	}
	
	bool hasDisease(human person) {
		return (person.isExposed or person.isInfected);
	}
	
	reflex randomTest when: shouldStartPolicy() and currentDay!=lastDay { // do test 1 times at the beginning of the day
		lastDay <- currentDay;
		write("testing");
		
		// test random unconfirmed people to see if they're postive.
		list<human> testedHumans <- nbTestPerDay among (human where(each.isConfirmed=false));
		
		loop person over: testedHumans {						
			if (hasDisease(person) and flip(truePositiveRate)) or (!hasDisease(person) and flip(1-trueNegativeRate)) {
				person.isConfirmed <- true;
				nbConfirmed <- nbConfirmed + 1;
				ask person {
					do startQuarantine();
				}
			}						
		}
	} 
}


//******************************************************

experiment Model3_2 until: (nbExposed = 0 and nbInfected = 0) {
	parameter "Number of people" var: humanNumber init: 1000 min:200 max:2000 step: 200;
	parameter "Initial infected" var: initialInfected init:10 min:1 max:100;
	parameter "Contagion in building" var: contagionInBuilding init: true among:[true, false];
	
	parameter "When to apply policy" var: policyTriggerMode init: POLICY_BY_TIME among: [POLICY_BY_TIME, POLICY_BY_INFECTED];	
	parameter "Policy no school" var: policyNoSchool init: 1 among:[0,1];
	parameter "Policy wear mask" var: policyWearMask init: 1 among:[0,1];
	parameter "Policy contain by age" var: policyContainByAge init: 1 among:[0,1];
	parameter "Policy total lockdown" var: policyTotalLockdown init: 1 among:[0,1];
	parameter "Policy free food" var: policyFreeFood init: 0 among:[0,1];	
	
	parameter "# Tests per day" var: nbTestPerDay init: 100 min: 0 max: 1000;
	parameter "Time until apply policy" var: timeToApply init: 5 min:0 max:100;
	parameter "Infected found until apply policy" var: infectedToApply init: 1 min: 1 max:100;	
	
	
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
		monitor "Confirmed" value: nbConfirmed;
		monitor "Recovered" value: nbRecovered;
		monitor "Hour:" value: currentHour;
		monitor "Day:" value: currentDay;		
	}
}