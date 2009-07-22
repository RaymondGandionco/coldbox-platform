<!-----------------------------------------------------------------------
********************************************************************************
Copyright 2005-2008 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
www.coldboxframework.com | www.luismajano.com | www.ortussolutions.com
********************************************************************************

Author: Luis Majano
Date:   July 28, 2006
Description: This is the framework's simple bean factory.

----------------------------------------------------------------------->
<cfcomponent name="BeanFactory"
			 hint="I am the ColdBox BeanFactory plugin that takes care of autowiring and dependency injection"
			 extends="coldbox.system.Plugin"
			 output="false"
			 cache="true"
			 cacheTimeout="0">

<!------------------------------------------- CONSTRUCTOR ------------------------------------------->

	<cffunction name="init" access="public" returntype="BeanFactory" output="false" hint="constructor">
		<!--- ************************************************************* --->
		<cfargument name="controller" type="any" required="true" hint="coldbox.system.Controller">
		<!--- ************************************************************* --->
		<cfscript>
			/* Super Init */
			super.Init(arguments.controller);
			
			/* Plugin Properties */
			setpluginName("Bean Factory");
			setpluginVersion("3.0");
			setpluginDescription("I am an awesome conventions,IoC and DI bean factory plugin.");
			setpluginAuthor("Luis Majano, Sana Ullah");
			setpluginAuthorURL("http://www.coldbox.org");
			
			instance.ModelsPath = getSetting("ModelsPath");
			instance.ModelsInvocationPath = getSetting("ModelsInvocationPath");
			instance.ModelsObjectCaching = getSetting("ModelsObjectCaching");
			instance.ModelsExternalLocation = getSetting("ModelsExternalLocation");
			instance.ModelsDefinitionFile = getSetting("ModelsDefinitionFile");
			
			instance.modelMappings = structnew();
			instance.NOT_FOUND = "_NOT_FOUND_";
			instance.dslMarker = "_wireme";
			if( settingExists("BeanFactory_dslMarker") ){
				instance.dslMarker = getSetting("BeanFactory_dslMarker");
			}
			
			/* Setup the Autowire DI Dictionary */
			setDICacheDictionary(CreateObject("component","coldbox.system.util.collections.BaseDictionary").init('DIMetadata'));
			
			return this;
		</cfscript>
	</cffunction>
	
	<cffunction name="configure" access="public" returntype="BeanFactory" hint="Configure the bean factory for operation" output="false" >
		<cfscript>
			var configFilePath = "/";
			var controller = getController();
			
			/* If AppMapping is not Blank check */
			if( controller.getSetting('AppMapping') neq "" ){
				configFilePath = configFilePath & controller.getSetting('AppMapping') & "/";
			}
			
			/* Setup the config Path */
			configFilePath = configFilePath & reReplace(instance.ModelsDefinitionFile,"^/","");
			
			/* Check if File Exists, else skip and log */
			if( fileExists(expandPath(configFilePath)) ){
				try{
					$include(configFilePath);
				}
				catch(Any e){
					$throw("Error including models definition file #configFilePath#. Error: #e.message#",
						   e.detail,
						   "BeanFactory.ModelsDefinitionFileIncludeException");
				}
			}
			else{
				getPlugin("Logger").warn("The BeanFactory definition file cannot be located -> #configFilePath#");
			}
			
			return this;
		</cfscript>
	</cffunction>

<!------------------------------------------- PUBLIC ------------------------------------------->
	
	<!--- Get Model Mappings --->
	<cffunction name="getModelMappings" access="public" returntype="struct" hint="Get the model mappings structure" output="false" >
		<cfreturn instance.modelMappings>
	</cffunction>
	
	<!--- Add Model Mapping --->
	<cffunction name="addModelMapping" access="public" returntype="void" hint="Add a new model mapping. Ex: addModelMapping('myBean','security.test.FormBean'). The alias can be a single item or a comma delimmitted list" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="alias" required="false" type="string" hint="The model alias to use, this can also be a list of aliases. Ex: SecurityService,Security">
		<cfargument name="path"  required="true" type="string" hint="The model class path (From the model conventions downward)">
		<!--- ************************************************************* --->
		<cfscript>
			var mappings = getModelMappings();
			var x = 1;
			/* Default Alias is from the path. */
			if(not structKeyExists(arguments,"alias") ){
				arguments.alias = listlast(arguments.path,".");
			}
			/* Loop */
			for(x=1;x lte listlen(arguments.alias); x=x+1){
				mappings[listgetAt(arguments.alias,x)] = arguments.path;
			}
		</cfscript> 
	</cffunction>
	
	<!--- Just create and call init, simple --->
	<cffunction name="create" hint="Create a named bean, simple as that. If the bean has an init() method, it will be called." access="public" output="false" returntype="Any">
		<!--- ************************************************************* --->
		<cfargument name="bean" 		required="true"  type="string" hint="The type of bean to create and return. Uses full cfc path mapping.Ex: coldbox.beans.ExceptionBean">
		<!--- ************************************************************* --->
		<cfscript>
			var beanInstance = "";
			try{
				/* Try to create bean */
				beanInstance = createObject("component","#arguments.bean#");
				
				/* check if an init */
				if( structKeyExists(beanInstance,"init") ){
					beanInstance = beanInstance.init();
				}
				
				/* Return object */
				return beanInstance;
			}
			Catch(Any e){
				$throw("Error creating bean: #arguments.bean#","#e.Detail#<br>#e.message#","ColdBox.plugins.BeanFactory.BeanCreationException");
			}
		</cfscript>
	</cffunction>
	
	<!--- Get Model --->
	<cffunction name="getModel" access="public" returntype="any" hint="Create or retrieve model objects by convention" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="name" 				required="true"  type="string" hint="The name of the model to retrieve">
		<cfargument name="useSetterInjection" 	required="false" type="boolean" hint="Whether to use setter injection alongside the annotations property injection. cfproperty injection takes precedence.">
		<cfargument name="onDICompleteUDF" 		required="false" type="string"	hint="After Dependencies are injected, this method will look for this UDF and call it if it exists. The default value is onDIComplete">
		<cfargument name="debugMode" 			required="false" type="boolean" hint="Debugging Mode or not">
		<cfargument name="stopRecursion"		required="false" type="string"  hint="A comma-delimmited list of stoprecursion classpaths.">
		<!--- ************************************************************* --->
		<cfscript>
			var oModel = 0;
			var modelClassPath = 0;
			var md = 0;
			var modelMappings = getModelMappings();
			var announceData = structnew();
			var isModelFinalized = false;
			
			/* Argument Overrides, else grab from existing settings */
			if( not structKeyExists(arguments,"useSetterInjection") ){
				arguments.useSetterInjection = getSetting("ModelsSetterInjection");
			}
			if( not structKeyExists(arguments,"onDICompleteUDF") ){
				arguments.onDICompleteUDF = getSetting("ModelsDICompleteUDF");
			}
			if( not structKeyExists(arguments,"debugMode") ){
				arguments.debugMode = getSetting("ModelsDebugMode");
			}
			if( not structKeyExists(arguments,"stopRecursion") ){
				arguments.stopRecursion = getSetting("ModelsStopRecursion");
			}
			
			/* Resolve name in Alias Checks */
			arguments.name = resolveModelAlias(arguments.name);
			
			/* Check if Model in Cache, if it is, return it and exit. */
			if ( getColdboxOCM().lookup(arguments.name) ){
				return getColdBoxOCM().get(arguments.name);
			}
			
			/* Locate the model Class Path */
			modelClassPath = locateModel(arguments.name);
		</cfscript>
		
		<!--- Create It if it exists --->
		<cfif NOT isModelFinalized>
			<cflock name="beanfactory.createmodel.#arguments.name#" type="exclusive" timeout="20" throwontimeout="true">
				<cfscript>
				if( NOT isModelFinalized ){
					/* Create the model object */
					oModel = createObject("component", modelClassPath);
					/* Verify Constructor: Init() and execute */
					if( structKeyExists(oModel,"init") ){
						oModel.init(argumentCollection=getConstructorArguments(oModel));
					}
					/* Persistence Checks */
					if( instance.ModelsObjectCaching ){
						/* Caching Metadata */
						md = getMetadata(oModel);
						if( not structKeyExists(md,"cache") or not isBoolean(md.cache) ){
							md.cache = false;
						}
						/* Singleton Support */
						if( structKeyExists(md,"singleton") AND isBoolean(md.singleton) ){
							md.cache = md.singleton;
							md.cacheTimeout = 0;
						}
						/* Are we Caching? */
						if( md.cache ){
							/* Prepare Timeouts and info. */
							if( not structKeyExists(md,"cachetimeout") or not isNumeric(md.cacheTimeout) ){
								md.cacheTimeout = "";
							}
							if( not structKeyExists(md,"cacheLastAccessTimeout") or not isNumeric(md.cacheLastAccessTimeout) ){
								md.cacheLastAccessTimeout = "";
							}
							/* Cache This Puppy. */
							getColdBoxOCM().set(arguments.name,oModel,md.cacheTimeout,md.CacheLastAccessTimeout);
						}
					}//end if caching enabled via settings.
					
					/* Autowire Dependencies */
					autowire(target=oModel,
							 useSetterInjection=arguments.useSetterInjection,
							 annotationCheck=false,
							 onDICompleteUDF=arguments.onDICompleteUDF,
							 debugMode=arguments.debugmode,
							 stopRecursion=arguments.stopRecursion);
					
					/* Announce Model Creation */
					announceData.oModel = oModel;
					announceData.modelName = arguments.name;
					announceInterception("afterModelCreation",announceData);
					/* Model Creation Finalized */
					isModelFinalized = true; 
				}
				</cfscript>
			</cflock>
		<cfelse>
			<cfthrow message="Model #arguments.name# could not be located."
					 type="plugin.BeanFactory.modelNotFoundException"
					 detail="The model object #arguments.name# cannot be located in the following locations: #instance.ModelsPath# OR #instance.ModelsExternalPath#">
		</cfif>
		
		<cfreturn oModel>
	</cffunction>
	
	<!--- Resolve Model Alias --->
	<cffunction name="resolveModelAlias" access="public" returntype="string" hint="Resolve the real name of any incoming argument model name or alias" output="false" >
		<cfargument name="name" required="true"  type="string" hint="The model alias or name to resolve">
		<cfscript>
		var mappings = getModelMappings();
		/* Resolve name in Aliases */
		if( structKeyExists(mappings,arguments.name) ){
			return mappings[arguments.name];
		}
		else{ 
			return arguments.name; 
		}
		</cfscript>
	</cffunction>
	
	<!--- Locate a Model Object --->
	<cffunction name="locateModel" access="public" returntype="string" hint="Get the location instantiation path for a model object. If the model location is not found, this method returns an empty string." output="false" >
		<cfargument name="name" required="true"  type="string" hint="The model to locate">
		<cfargument name="resolveAlias"  type="boolean" required="false" default="false" hint="Resolve model aliases">
		<cfscript>
			var checkPath = 0;
			var checkExternalPath = 0;
			var extPaths = instance.ModelsExternalLocation;
			var thisExtPath = "";
			var x=1;
			
			/* Resolve Alias? */
			if( arguments.resolveAlias ){
				arguments.name = resolveModelAlias(arguments.name);
			}
			
			/* TODO: Create a RefLocationMap, so location routines are only done once. */
			
			/* Conventions Check First */
			checkPath = instance.ModelsPath & "/" & replace(arguments.name,".","/","all") & ".cfc";
			
			/* Class Path Determination */
			if( fileExists(checkPath) ){
				return instance.ModelsInvocationPath & "." & arguments.name;
			}
			else{
				/* Check External Locations in declared Order */
				for(x=1; x lte listLen(extPaths);x=x+1){
					/* Compose Object Location */
					thisExtPath = listGetAt(extPaths,x);
					checkExternalPath = "/" & replace(thisExtPath,".","/","all")  & "/" & replace(arguments.name,".","/","all") & ".cfc";
					/* Check if located */
					if( fileExists(expandPath(checkExternalPath)) ){
						return  thisExtPath & "." & arguments.name;
					}
				}
			}
			
			return "";
		</cfscript>
	</cffunction>
	
	<!--- Check if the model exists in a path --->
	<cffunction name="containsModel" access="public" returntype="boolean" hint="Checks if the factory has a model object definition found" output="false" >
		<cfargument name="name" required="true"  type="string" hint="The name of the model to check">
		<cfargument name="resolveAlias"  type="boolean" required="false" default="false" hint="Resolve model aliases">
		<cfscript>
			/* Resolve Alias? */
			if( arguments.resolveAlias ){ arguments.name = resolveModelAlias(arguments.name); }
			/* Try to Locate */
			if( len(locateModel(arguments.name)) ){
				return true;
			}
			else{
				return false;
			}
		</cfscript>
	</cffunction>
	
	
	<!--- Populate a model object from the request Collection --->
	<cffunction name="populateModel" access="public" output="false" returntype="Any" hint="Populate a named or instantiated model (java/cfc) from the request collection items">
		<!--- ************************************************************* --->
		<cfargument name="model" 			required="true"  type="any" 	hint="The name of the model to get and populate or the acutal model object. If you already have an instance of a model, then use the populateBean() method">
		<cfargument name="scope" 			required="false" type="string"  default=""   hint="Use scope injection instead of setters population. Ex: scope=variables.instance."/>
		<cfargument name="trustedSetter"  	required="false" type="boolean" default="false" hint="If set to true, the setter method will be called even if it does not exist in the bean"/>
		<cfargument name="include"  		required="false" type="string"  default="" hint="A list of keys to include in the population">
		<cfargument name="exclude"  		required="false" type="string"  default="" hint="A list of keys to exclude in the population">
		<!--- ************************************************************* --->
		<cfscript>
			arguments.memento = controller.getRequestService().getContext().getCollection();
			
			/* Do we have a model or name */
			if( isSimpleValue(arguments.model) ){
				arguments.target = getModel(model);
			}
			else{
				arguments.target = arguments.model;
			}
			
			/* Inflate from Request Collection */
			return populateFromStruct(argumentCollection=arguments);			
		</cfscript>
	</cffunction>

	<!--- Populate a bean from the request Collection --->
	<cffunction name="populateBean" access="public" output="false" returntype="Any" hint="Populate a named or instantiated bean (java/cfc) from the request collection items">
		<!--- ************************************************************* --->
		<cfargument name="target" 			required="true" 	type="any" 	hint="This can be an instantiated bean object or a bean instantitation path as a string.  This method follows the bean contract (set{property_name}). Example: setUsername(), setfname()">
		<cfargument name="scope" 			required="false" 	type="string"   default=""   hint="Use scope injection instead of setters population. Ex: scope=variables.instance."/>
		<cfargument name="trustedSetter"  	required="false" type="boolean" default="false" hint="If set to true, the setter method will be called even if it does not exist in the bean"/>
		<cfargument name="include"  		required="false" type="string"  default="" hint="A list of keys to include in the population">
		<cfargument name="exclude"  		required="false" type="string"  default="" hint="A list of keys to exclude in the population">
		<!--- ************************************************************* --->
		<cfscript>
			arguments.memento = controller.getRequestService().getContext().getCollection();
			
			/* Inflate from Request Collection */
			return populateFromStruct(argumentCollection=arguments);			
		</cfscript>
	</cffunction>
	
	<!--- Populate a bean from a structure --->
	<cffunction name="populateFromJSON" access="public" returntype="any" hint="Populate a named or instantiated bean from a json string" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="target" 			required="true" 	type="any" 		hint="This can be an instantiated bean object or a bean instantitation path as a string. If you pass an instantiation path and the bean has an 'init' method. It will be executed. This method follows the bean contract (set{property_name}). Example: setUsername(), setfname()">
		<cfargument name="JSONString"   	required="true" 	type="string" 	hint="The JSON string to populate the object with. It has to be valid JSON and also a structure with name-key value pairs. ">
		<cfargument name="scope" 			required="false" 	type="string"   default=""   hint="Use scope injection instead of setters population. Ex: scope=variables.instance."/>
		<cfargument name="trustedSetter"  	required="false" type="boolean" default="false" hint="If set to true, the setter method will be called even if it does not exist in the bean"/>
		<cfargument name="include"  		required="false" type="string"  default="" hint="A list of keys to include in the population">
		<cfargument name="exclude"  		required="false" type="string"  default="" hint="A list of keys to exclude in the population">
		<!--- ************************************************************* --->
		<cfscript>
			/* Inflate JSON */
			arguments.memento = getPlugin("JSON").decode(arguments.JSONString);
			
			/* populate and return */
			return populateFromStruct(argumentCollection=arguments);
		</cfscript>
	</cffunction>
	
	<!--- Populate from Query --->
	<cffunction name="populateFromQuery" access="public" returntype="Any" hint="Populate a named or instantiated bean from query" output="false">
		<!--- ************************************************************* --->
		<cfargument name="target"  			required="true"  type="any" 	 hint="This can be an instantiated bean object or a bean instantitation path as a string. If you pass an instantiation path and the bean has an 'init' method. It will be executed. This method follows the bean contract (set{property_name}). Example: setUsername(), setfname()">
		<cfargument name="qry"       		required="true"  type="query"   hint="The query to popluate the bean object with">
		<cfargument name="RowNumber" 		required="false" type="Numeric" hint="The query row number to use for population" default="1">
		<cfargument name="scope" 			required="false" type="string"   default=""   hint="Use scope injection instead of setters population. Ex: scope=variables.instance."/>
		<cfargument name="trustedSetter"  	required="false" type="boolean" default="false" hint="If set to true, the setter method will be called even if it does not exist in the bean"/>
		<cfargument name="include"  		required="false" type="string"  default="" hint="A list of keys to include in the population">
		<cfargument name="exclude"  		required="false" type="string"  default="" hint="A list of keys to exclude in the population">
		<!--- ************************************************************* --->
		<cfscript>
			//by default to take values from first row of the query
			var row = arguments.RowNumber;
			//columns array
			var cols = listToArray(arguments.qry.columnList);
			//new struct to hold query colum name and value
			var i   = 1;
			arguments.memento = structnew();
			
			//build the struct from the query row
			for(i = 1; i lte arraylen(cols); i = i + 1){
				arguments.memento[cols[i]] = arguments.qry[cols[i]][row];
			}		
			
			//populate bean and return
			return populateFromStruct(argumentCollection=arguments);
		</cfscript>
	</cffunction>

	<!--- Populate a bean from a structure --->
	<cffunction name="populateFromStruct" access="public" returntype="any" hint="Populate a named or instantiated bean from a structure" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="target" 			required="true"  type="any" 	hint="This can be an instantiated bean object or a bean instantitation path as a string. If you pass an instantiation path and the bean has an 'init' method. It will be executed. This method follows the bean contract (set{property_name}). Example: setUsername(), setfname()">
		<cfargument name="memento"  		required="true"  type="struct" 	hint="The structure to populate the object with.">
		<cfargument name="scope" 			required="false" type="string"  hint="Use scope injection instead of setters population."/>
		<cfargument name="trustedSetter"  	required="false" type="boolean" default="false" hint="If set to true, the setter method will be called even if it does not exist in the bean"/>
		<cfargument name="include"  		required="false" type="string"  default="" hint="A list of keys to include in the population">
		<cfargument name="exclude"  		required="false" type="string"  default="" hint="A list of keys to exclude in the population">
		<!--- ************************************************************* --->
		<cfscript>
			var beanInstance = 0;
			var key = "";
			var pop = false;
			var scopeInjection = false;
			
			try{
				/* Local Ref to bean instance */
				if( isSimpleValue(arguments.target) ){
					beanInstance = create(arguments.target);
				}
				else{
					beanInstance = arguments.target;
				}
				
				/* Determine Method of population */
				if( structKeyExists(arguments,"scope") and len(trim(arguments.scope)) neq 0 ){
					scopeInjection = true;
					getPlugin("MethodInjector").start(beanInstance);
				}
				
				/* Populate Bean */
				for(key in arguments.memento){
					pop = false;
					/* Include List? */
					if( len(arguments.include) AND listFindNoCase(arguments.include,key) ){
						pop = true;
					}
					/* Exclude List? */
					else if( len(arguments.exclude) AND NOT listFindNoCase(arguments.exclude,key) ){
						pop = true;
					}
					else{
						pop = true;
					}
					
					/* Pop? */
					if( pop ){
						/* Scope Injection? */
						if( scopeInjection ){
							beanInstance.populatePropertyMixin(propertyName=key,propertyValue=arguments.memento[key],scope=arguments.scope);
						}
						/* Check if setter exists, evaluate is used, so it can call on java/groovy objects */
						else if( structKeyExists(beanInstance,"set" & key) or arguments.trustedSetter ){
							evaluate("beanInstance.set#key#(arguments.memento[key])");
						}
					}
					
				}//end for loop
				
				/* Stop The Mixins*/
				if( scopeInjection ){
					getPlugin("MethodInjector").stop(beanInstance);
				}
				
				return beanInstance;
			}
			catch(Any e){
				if (isObject(arguments.memento[key]) OR isCustomFunction(arguments.memento[key])){
					arguments.keyTypeAsString = getMetaData(arguments.memento[key]).name;
				} 
				else{
		        	arguments.keyTypeAsString = arguments.memento[key].getClass().toString();
				}
				$throw(type="ColdBox.plugins.BeanFactory.PopulateBeanException",
					  message="Error populating bean #getMetaData(beanInstance).name# with argument #key# of type #arguments.keyTypeAsString#.",
					  detail="#e.Detail#<br>#e.message#");
			}
		</cfscript>
	</cffunction>

	<!--- Autowire --->
	<cffunction name="autowire" access="public" returntype="void" output="false" hint="Autowire an object using the ColdBox DSL">
		<!--- ************************************************************* --->
		<cfargument name="target" 				required="true" 	type="any" 		hint="The object to autowire">
		<cfargument name="useSetterInjection" 	required="false" 	type="boolean" 	default="true"	hint="Whether to use setter injection alongside the annotations property injection. cfproperty injection takes precedence.">
		<cfargument name="annotationCheck" 		required="false" 	type="boolean"  default="false" hint="This value determines if we check if the target contains an autowire annotation in the cfcomponent tag: autowire=true|false, it will only autowire if that metadata attribute is set to true. The default is false, which will autowire automatically.">
		<cfargument name="onDICompleteUDF" 		required="false" 	type="string"	default="onDIComplete" hint="After Dependencies are injected, this method will look for this UDF and call it if it exists. The default value is onDIComplete">
		<cfargument name="debugMode" 			required="false" 	type="boolean"  default="false" hint="Whether to log debug messages. Default is false">
		<cfargument name="stopRecursion" 		required="false" 	type="string"   default="" hint="The stop recursion class. Ex: transfer.com.TransferDecorator. By default all ColdBox base classes are included.">
		<!--- ************************************************************* --->
		<cfscript>
			/* Targets */
			var targetObject = arguments.target;
			var MetaData = getMetaData(targetObject);
			var targetCacheKey = MetaData.name;
			
			/* Dependencies */
			var thisDependency = instance.NOT_FOUND;
			
			/* Metadata entry structures */
			var mdEntry = "";
			var targetDIEntry = "";
			var dependenciesLength = 0;
			var x = 1;
			var tmpBean = "";
			
			/* Helpers */
			var oMethodInjector = '';
		</cfscript>
		
		<!--- Do we have the incoming target object's data in the cache? or caching disabled for objects --->
		<cfif not getDICacheDictionary().keyExists(targetCacheKey) OR NOT instance.ModelsObjectCaching>
			<cflock type="exclusive" name="plugins.autowire.#targetCacheKey#" timeout="30" throwontimeout="true">
				<cfscript>
					/* Double Lock for thread concurrency */
					if ( not getDICacheDictionary().keyExists(targetCacheKey) ){
						/* Get Empty Default MD Entry */
						mdEntry = getNewMDEntry();
												
						/* Annotation Check*/
						if( not arguments.annotationCheck ){
							MetaData.autowire = true;
						}
						else if ( not structKeyExists(MetaData,"autowire") or not isBoolean(MetaData["autowire"]) ){
							MetaData.autowire = false;
							mdEntry.autowire = false;
						}
						
						/* Lookup Dependencies if using autowire */
						if ( MetaData["autowire"] ){
							/* Set md entry to true for autowiring */
							mdEntry.autowire = true;
							/* Recurse for dependencies here, in order to build them. */
							mdEntry.dependencies = parseMetadata(MetaData,mdEntry.dependencies,arguments.useSetterInjection,arguments.stopRecursion);
						}
						
						/* Set Entry in dictionary */
						getDICacheDictionary().setKey(targetCacheKey,mdEntry);
					}
				</cfscript>
			</cflock>
		</cfif>
			
		<cfscript>
		/* We are now assured that the DI cache has data. */
		targetDIEntry = getDICacheDictionary().getKey(targetCacheKey);
		/* Do we Inject Dependencies, are we AutoWiring */
		if ( targetDIEntry.autowire ){
			/* Dependencies Length */
			dependenciesLength = arrayLen(targetDIEntry.dependencies);
			if( dependenciesLength gt 0 ){
				/* References */
				oMethodInjector = getPlugin("MethodInjector");
				/* Let's inject our mixins */
				oMethodInjector.start(targetObject);
				/* Loop over dependencies and inject. */
				for(x=1; x lte dependenciesLength; x=x+1){
					/* Get Dependency */
					thisDependency = getDSLDependency(definition=targetDIEntry.dependencies[x],
													  debugMode=arguments.debugmode);
					/* Validate it */
					if( isSimpleValue(thisDependency) and thisDependency eq instance.NOT_FOUND ){
						/* Only log if debugmode, else no injection */
						if( arguments.debugMode ){
							getPlugin("Logger").warn("Dependency: #targetDIEntry.dependencies[x].toString()# Not Found");
						}
					}
					else{
						/* Inject dependency*/
						injectBean(targetBean=targetObject,
								   beanName=targetDIEntry.dependencies[x].name,
								   beanObject=thisDependency,
								   scope=targetDIEntry.dependencies[x].scope);
						/* Debug Mode Check */
						if( arguments.debugMode ){
							getPlugin("Logger").info("Dependency: #targetDIEntry.dependencies[x].toString()# --> injected into #getMetadata(targetObject).name#.");
						}
					}
				}//end for loop of dependencies.
				
				// Process After ID Complete
				processAfterCompleteDI(targetObject,onDICompleteUDF);
				// Let's cleanup our mixins
				getPlugin("MethodInjector").stop(targetObject);
				
			}// if dependencies found.
		}//if autowiring			
	</cfscript>
	</cffunction>
	
<!------------------------------------------- PRIVATE ------------------------------------------->
	
	<!--- getConstructorArguments --->
	<cffunction name="getConstructorArguments" output="false" access="private" returntype="struct" hint="The constructor argument collection for a model object">
		<!--- ************************************************************* --->
		<cfargument name="model" 				required="true" 	type="any"		default="" hint="The model object"/>
		<cfargument name="debugMode" 			required="false" 	type="boolean"  default="false" hint="Whether to log debug messages. Default is false">
		<!--- ************************************************************* --->
		<cfscript>
			var md = getMetadata(model.init);
			var params = md.parameters;
			var paramLen = ArrayLen(md.parameters);
			var x =1;
			var args = structnew();
			var definition = structnew();
			
			/* Loop Over Arguments */
			for(x=1;x lte paramLen; x=x+1){
				/* Check Marker and IOC Framework*/
				if( structKeyExists(params[x],instance.dslMarker) ){
					definition.type = params[x][instance.dslMarker];
				}
				/* If IOC Framework defined, let setter be defaulted to IOC */
				else if(getSetting("IOCFramework") neq ""){
					definition.type = "ioc";
				}
				/* Else default to model integration */
				else{
					definition.type = "model";
				}
				/* Other Defaults */
				definition.name = params[x].name;
				definition.scope="";
				
				/* Get Dependency */
				args[definition.name] = getDSLDependency(definition=definition,debugMode=arguments.debugMode);
			}
			
			return args;			
		</cfscript>
	</cffunction>
	
	<!--- getDSLDependency --->
	<cffunction name="getDSLDependency" output="false" access="private" returntype="any" hint="get a dsl dependency">
		<!--- ************************************************************* --->
		<cfargument name="definition" 			required="true" 	type="any" hint="The dependency definition structure">
		<cfargument name="debugMode" 			required="false" 	type="boolean"  default="false" hint="Whether to log debug messages. Default is false">
		<!--- ************************************************************* --->
		<cfscript>
			var dependency = instance.NOT_FOUND;
			var thisType = listFirst(arguments.Definition.type,":");
			
			/* Determine Type of Injection according to Type */
			if( thisType eq "ioc" ){
				dependency = getIOCDependency(arguments.Definition,arguments.debugmode);
			}
			else if (thisType eq "ocm"){
				dependency = getOCMDependency(arguments.Definition,arguments.debugmode);
			}
			else if ( thisType eq "coldbox" ){
				/* Try to inject coldbox dependencies */
				dependency = getColdboxDSL(arguments.Definition);
			}
			else if ( thisType eq "model" ){
				/* Try to inject model dependencies */
				dependency = getModelDSL(definition=arguments.Definition,
									   	 debugMode=arguments.debugMode);
			}	
			else if ( thisType eq "webservice" ){
				/* Try to inject webservice dependencies */
				dependency = getWebserviceDSL(arguments.Definition);
			}
			
			return dependency;
		</cfscript>
	</cffunction>
	
	<!--- getWebserviceDSL --->
	<cffunction name="getWebserviceDSL" access="private" returntype="any" hint="Get webservice dependencies" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="Definition" 	required="true" type="any" hint="The dependency definition structure">
		<!--- ************************************************************* --->
		<cfscript>
			var oWebservices = getPlugin("Webservices");
			var thisDependency = arguments.Definition;
			var webserviceName = listLast(thisDependency.type);
			/* Get Dependency */
			return oWebservices.getWSobj(webserviceName);
		</cfscript>
	</cffunction>	
	
	<!--- getLibraryDSL --->
	<cffunction name="getLibraryDSL" access="private" returntype="any" hint="Get dependencies using the library dependency DSL" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="Definition" 	required="true" type="any" hint="The dependency definition structure">
		<!--- ************************************************************* --->
		<cfscript>
			var thisDependency = arguments.Definition;
			var thisType = thisDependency.type;
			var thisTypeLen = listLen(thisType,":");
			var thisLocationType = "";
			var thisLocationKey = "";
			var locatedDependency = instance.NOT_FOUND;
			
			/* 1 stage dependency dsl : Get Library */
			if(thisTypeLen eq 1){
				/* Get Library according to Property Name */
				locatedDependency = getModel(arguments.Definition.name);
			}
			/* 2 stage dependency dsl : Get Library */
			else if(thisTypeLen eq 2){
				thisLocationType = getToken(thisType,2,":");
				/* Get model object*/
				locatedDependency = getModel(thisLocationType);
			}
			/* 3 stage dependency dsl : Library Factories*/
			else if(thisTypeLen eq 3){
				thisLocationType = getToken(thisType,2,":");
				thisLocationKey = getToken(thisType,3,":");
				/* Call model method to get dependency */
				locatedDependency = evaluate("getModel(thisLocationType).#thisLocationKey#()");
			}//end 3 stage DSL
			
			return locatedDependency;
		</cfscript>
	</cffunction>
	
	<!--- getModelDSL --->
	<cffunction name="getModelDSL" access="private" returntype="any" hint="Get dependencies using the model dependency DSL" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="definition" 			required="true" 	type="any" hint="The dependency definition structure">
		<cfargument name="debugMode" 			required="false" 	type="boolean"  default="false" hint="Whether to log debug messages. Default is false">
		<!--- ************************************************************* --->
		<cfscript>
			var thisDependency = arguments.Definition;
			var thisType = thisDependency.type;
			var thisTypeLen = listLen(thisType,":");
			var thisLocationType = "";
			var thisLocationKey = "";
			var locatedDependency = instance.NOT_FOUND;
			var args = structnew();
			
			/* Prepare Arguments */
			args.debugmode = arguments.debugMode;
			
			/* 1 stage dependency dsl : Get Model */
			if(thisTypeLen eq 1){
				args.name = arguments.Definition.name;
			}
			/* 2 stage dependency dsl : Get Model */
			else if(thisTypeLen eq 2){
				thisLocationType = getToken(thisType,2,":");
				args.name = thisLocationType;
			}
			/* 3 stage dependency dsl : Model Factories*/
			else if(thisTypeLen eq 3){
				thisLocationType = getToken(thisType,2,":");
				thisLocationKey = getToken(thisType,3,":");
				args.name = thisLocationType;
			}//end 3 stage DSL
			
			/* Check if model Exists */
			if( containsModel(name=args.name,resolveAlias=true) ){
				/* Get Model */
				locatedDependency = getModel(argumentCollection=args);
				/* Factories: TODO: Need Encap here */
				if( thisTypeLen eq 3 ){
					locatedDependency = evaluate("locatedDependency.#thisLocationKey#()");
				}
			}
			else if (arguments.debugMode){
				getPlugin("Logger").warn("BeanFactory.getModelDSL - Model :#args.name# was not found. Definition=#thisDependency.toString()#");
			}
			
			return locatedDependency;
		</cfscript>
	</cffunction>
	
	<!--- getColdboxDSL --->
	<cffunction name="getColdboxDSL" access="private" returntype="any" hint="Get dependencies using the coldbox dependency DSL" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="definition" 	required="true" type="any" hint="The dependency definition structure">
		<!--- ************************************************************* --->
		<cfscript>
			var thisDependency = arguments.Definition;
			var thisType = thisDependency.type;
			var thisTypeLen = listLen(thisType,":");
			var thisLocationType = "";
			var thisLocationKey = "";
			var locatedDependency = instance.NOT_FOUND;
			
			/* 1 stage dependency: ColdBox */
			if( thisTypeLen eq 1 ){
				/* Coldbox Reference is the only one available on 1 stage DSL */
				locatedDependency = getController();
			}
			/* 2 stage dependencies. Coldbox:ConfigBean */
			else if(thisTypeLen eq 2){
				thisLocationKey = getToken(thisType,2,":");
				switch( thisLocationKey ){
					case "configbean" 			: { locatedDependency = getSettingsBean(); break; }
					case "mailsettingsbean"		: { locatedDependency = getMailSettings(); break; }
					case "loaderService"		: { locatedDependency = getController().getLoaderService(); break; }
					case "requestService"		: { locatedDependency = getController().getrequestService(); break; }
					case "debuggerService"		: { locatedDependency = getController().getDebuggerService(); break; }
					case "pluginService"		: { locatedDependency = getController().getPluginService(); break; }
					case "handlerService"		: { locatedDependency = getController().gethandlerService(); break; }
					case "interceptorService"	: { locatedDependency = getController().getinterceptorService(); break; }
					case "cacheManager"			: { locatedDependency = getController().getColdboxOCM(); break; }
				}//end of services
			}
			/* 3 stage dependencies */
			else if(thisTypeLen eq 3){
				thisLocationType = getToken(thisType,2,":");
				thisLocationKey = getToken(thisType,3,":");
				switch(thisLocationType){
					case "setting" 				: { locatedDependency = getSetting(thisLocationKey); break; }
					case "plugin" 				: { locatedDependency = getPlugin(thisLocationKey); break; }
					case "myplugin" 			: { locatedDependency = getMyPlugin(thisLocationKey); break; }
					case "datasource" 			: { locatedDependency = getDatasource(thisLocationKey); break; }
				}//end of services
			}//end 3 stage DSL
			
			return locatedDependency;
		</cfscript>
	</cffunction>

	<!--- getIOCDependency --->
	<cffunction name="getIOCDependency" access="private" returntype="any" hint="Get an IOC dependency" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="definition" 	required="true" type="any" hint="The dependency definition structure">
		<cfargument name="debugMode" 	required="false" 	type="boolean"  default="false" hint="Whether to log debug messages. Default is false">
		<!--- ************************************************************* --->
		<cfscript>
			var oIOC = getPlugin("IOC");
			var thisDependency = arguments.Definition;
			var thisType = thisDependency.type;
			var thisTypeLen = listLen(thisType,":");
			var thisLocationKey = "";
			var locatedDependency = instance.NOT_FOUND;
			
			//dump(arguments.definition);abort();
			/* 1 stage dependency: ioc only*/
			if( thisTypeLen eq 1 ){
				thisLocationKey = thisDependency.name;
			}
			/* 2 stage dependencies. ioc:beanName */
			else if(thisTypeLen eq 2){
				thisLocationKey = getToken(thisType,2,":");
			}
			
			/* Check for Bean */
			if( oIOC.getIOCFactory().containsBean(thisLocationKey) ){
				locatedDependency = oIOC.getBean(thisLocationKey);
			}
			else{
				getPlugin("Logger").warn("BeanFactory.getIOCDependency - Bean :#thisLocationKey# was not found. Definition=#thisDependency.toString()#");
			}
					
			return locatedDependency;
		</cfscript>
	</cffunction>
	
	<!--- getOCMDependency --->
	<cffunction name="getOCMDependency" access="private" returntype="any" hint="Get OCM dependencies" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="definition" 	required="true" type="any" hint="The dependency definition structure">
		<cfargument name="debugMode" 	required="false" 	type="boolean"  default="false" hint="Whether to log debug messages. Default is false">
		<!--- ************************************************************* --->
		<cfscript>
			var oOCM = getColdboxOCM();
			var thisDependency = arguments.Definition;
			var thisType = thisDependency.type;
			var thisTypeLen = listLen(thisType,":");
			var thisLocationKey = "";
			var locatedDependency = instance.NOT_FOUND;
			
			/* 1 stage dependency: ocm only */
			if( thisTypeLen eq 1 ){
				thisLocationKey = thisDependency.name;		
			}
			/* 2 stage dependencies. ocm:ObjectKey */
			else if(thisTypeLen eq 2){
				thisLocationKey = getToken(thisType,2,":");			
			}		
			
			/* Verify that dependency exists in the Cache container. */
			if( oOCM.lookup(thisLocationKey) ){
				locatedDependency = oOCM.get(thisLocationKey);
			}	
			else if( arguments.debugMode ){
				getPlugin("Logger").warn("BeanFactory.getOCMDependency - Bean :#thisLocationKey# not found in the Cache. Definition=#thisDependency.toString()#");
			}
			
			return locatedDependency;
		</cfscript>
	</cffunction>
	
	<!--- Get an object's dependencies via metadata --->
	<cffunction name="parseMetadata" returntype="array" access="private" output="false" hint="I get a components dependencies via searching for 'setters'">
		<!--- ************************************************************* --->
		<cfargument name="metadata" 			required="true"  type="any" 	hint="The recursive metadata">
		<cfargument name="dependencies" 		required="true"  type="array" 	hint="The dependencies">
		<cfargument name="useSetterInjection" 	required="false" type="boolean" default="true"	hint="Whether to use setter injection alongside the annotations property injection. cfproperty injection takes precedence.">
		<cfargument name="stopRecursion" 		required="false" type="string" 	default="" hint="The stop recursion class">
		<!--- ************************************************************* --->
		<cfscript>
			var x = 1;
			var md = arguments.metadata;
			var entry = structnew();
			var cbox_reserved_functions = "setSetting,setDebugMode,setNextEvent,setNextRoute,setController,settingExists,setPluginName,setPluginVersion,setPluginDescription,setPluginAuthor,setPluginAuthorURL,setProperty,setproperties";
			var foundDependencies = "";
			
			/* Look for Object's attributes, and override if found. */
			if( structKeyExists(md,"autowire_stoprecursion") ){
				arguments.stopRecursion = md["autowire_stoprecursion"];
			}
			if( structKeyExists(md,"autowire_setterinjection") and isBoolean(md["autowire_setterinjection"]) ){
				arguments.useSetterInjection = md["autowire_setterinjection"];
			}
			
			/* Look For cfProperties */
			if( structKeyExists(md,"properties") and ArrayLen(md.properties) gt 0){
				for(x=1; x lte ArrayLen(md.properties); x=x+1 ){
					
					/* Check types are valid for autowiring. */
					if( structKeyExists(md.properties[x],"type") AND 
						( findnocase("webservice",md.properties[x].type) OR
						  findnocase("model",md.properties[x].type) OR
						  findnocase("coldbox",md.properties[x].type) OR
						  findnocase("ioc",md.properties[x].type) OR
						  findnocase("ocm",md.properties[x].type) )  	
					){
						/* New MD Entry */
						entry = structnew();
						/* Scope Check */
						if( not structKeyExists(md.properties[x],"scope") ){
							md.properties[x].scope = "variables";
						}		
						/* Setup Entry */
						entry.name 	= md.properties[x].name;
						entry.scope = md.properties[x].scope;
						entry.type 	= md.properties[x].type;
						
						/* Add to found list */
						listAppend(foundDependencies,entry.name);
						
						/* Add Property Dependency */
						ArrayAppend( arguments.dependencies, entry );
					}
					
				}//end for loop		
			}//end if properties found.
			
			/* Look for cfFunctions and if setter injection is enabled. */		
			if( arguments.useSetterInjection and structKeyExists(md, "functions") ){
				for(x=1; x lte ArrayLen(md.functions); x=x+1 ){
					/* Verify we have a setter */
					if( left(md.functions[x].name,3) eq "set" AND NOT 
					    listFindNoCase(cbox_reserved_functions,md.functions[x].name) ){
						
						/* New MD Entry */
						entry = structnew();
						entry.name = Right(md.functions[x].name, Len(md.functions[x].name)-3);
						entry.scope = "";
						
						/* Check Marker and IOC Framework*/
						if( structKeyExists(md.functions[x],instance.dslMarker) ){
							entry.type = md.functions[x][instance.dslMarker];
						}
						/* If IOC Framework defined, let setter be defaulted to IOC */
						else if(getSetting("IOCFramework") neq ""){
							entry.type = "ioc";
						}
						/* Else default to model integration */
						else{
							entry.type = "model";
						}
						
						/* Add if not already in properties */
						if( not listFindNoCase(foundDependencies,entry.name) ){
							/* Found Setter, append property Name */
							listAppend(foundDependencies,entry.name);
							ArrayAppend(arguments.dependencies, entry);
						}
					
					}//end if setter found.
				}//end loop of functions
			}//end if functions found
			
			/* Start Registering inheritances */
			if ( structKeyExists(md, "extends") 
				 AND 
				 stopClassRecursion(classname=md.extends.name,stopRecursion=arguments.stopRecursion) EQ FALSE){
				/* Recursive lookup */
				arguments.dependencies = parseMetadata(md.extends,arguments.dependencies,arguments.useSetterInjection,arguments.stopRecursion);
			}
			
			/* return the dependencies found */
			return arguments.dependencies;
		</cfscript>	
	</cffunction>
	
	<!--- Stop Recursion --->
	<cffunction name="stopClassRecursion" access="private" returntype="boolean" hint="Should we stop recursion or not due to class name found" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="classname" 		required="true" type="string" hint="The class name to check">
		<cfargument name="stopRecursion" 	required="true" type="string" hint="The comma delimmitted list of stoprecursion classes">
		<!--- ************************************************************* --->
		<cfscript>
			var coldboxReservedClasses = "coldbox.system.Plugin,coldbox.system.EventHandler,coldbox.system.Interceptor";
			var x = 1;
			
			/* Append Coldbox Classes */
			arguments.stopRecursion = listAppend(arguments.stopRecursion,coldboxReservedClasses);
			
			/* Try to find a match */
			for(x=1;x lte listLen(arguments.stopRecursion); x=x+1){
				if( CompareNoCase(listGetAt(arguments.stopRecursion,x),arguments.classname) eq 0){
					return true;
				}
			}
			
			return false;
		</cfscript>
	</cffunction>
	
	<!--- Inject Bean --->
	<cffunction name="injectBean" access="private" returntype="void" output="false" hint="Inject a bean with dependencies via setters or property injections">
		<!--- ************************************************************* --->
		<cfargument name="targetBean"  	 type="any" 	required="true" hint="The bean that will be injected with dependencies" />
		<cfargument name="beanName"  	 type="string" 	required="true" hint="The name of the property to inject"/>
		<cfargument name="beanObject" 	 type="any" 	required="true" hint="The bean object to inject." />
		<cfargument name="scope" 		 type="string"  required="true" hint="The scope to inject a property into.">
		<!--- ************************************************************* --->
		<cfscript>
			var argCollection = structnew();
			argCollection[arguments.beanName] = arguments.beanObject;
		</cfscript>
		<!--- Property or Setter --->
		<cfif len(arguments.scope) eq 0>
			<!--- Call our mixin invoker --->
			<cfinvoke component="#arguments.targetBean#" method="invokerMixin">
				<cfinvokeargument name="method"  		value="set#arguments.beanName#">
				<cfinvokeargument name="argCollection"  value="#argCollection#">
			</cfinvoke>
		<cfelse>
			<!--- Call our property injector mixin --->
			<cfinvoke component="#arguments.targetBean#" method="injectPropertyMixin">
				<cfinvokeargument name="propertyName"  	value="#arguments.beanName#">
				<cfinvokeargument name="propertyValue"  value="#arguments.beanObject#">
				<cfinvokeargument name="scope"			value="#arguments.scope#">
			</cfinvoke>	
		</cfif>			
	</cffunction>
	
	<!--- Process After DI Complete --->
	<cffunction name="processAfterCompleteDI" hint="see if we have a method to call after DI, and if so, call it" access="private" returntype="void" output="false">
		<!--- ************************************************************* --->
		<cfargument name="targetObject" 	required="Yes"  	type="any"	hint="the target object to call on">
		<cfargument name="onDICompleteUDF" 	required="false" 	type="string"	default="onDIComplete" hint="After Dependencies are injected, this method will look for this UDF and call it if it exists.">
		<!--- ************************************************************* --->
		<!--- Check if method exists --->
		<cfif StructKeyExists(arguments.targetObject, arguments.onDICompleteUDF )>
			<!--- Call our mixin invoker --->
			<cfinvoke component="#arguments.targetObject#" method="invokerMixin">
				<cfinvokeargument name="method"  		value="#arguments.onDICompleteUDF#">
			</cfinvoke>
		</cfif>
	</cffunction>
	
	<!--- Get a new MD cache entry structure --->
	<cffunction name="getNewMDEntry" access="private" returntype="struct" hint="Get a new metadata entry structure" output="false" >
		<cfscript>
			var mdEntry = structNew();
			
			mdEntry.autowire = false;
			mdEntry.dependencies = Arraynew(1);
			
			return mdEntry;
		</cfscript>
	</cffunction>

	<!--- Get Set DI CACHE Dictionary --->
	<cffunction name="getDICacheDictionary" access="private" output="false" returntype="coldbox.system.util.collections.BaseDictionary" hint="Get DICacheDictionary">
		<cfreturn instance.DICacheDictionary/>
	</cffunction>
	<cffunction name="setDICacheDictionary" access="private" output="false" returntype="void" hint="Set DICacheDictionary">
		<cfargument name="DICacheDictionary" type="coldbox.system.util.collections.BaseDictionary" required="true"/>
		<cfset instance.DICacheDictionary = arguments.DICacheDictionary/>
	</cffunction>
	
</cfcomponent>