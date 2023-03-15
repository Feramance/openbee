------ Second_Fry's openbee modular fork (v2.0.0)
------ Original idea and code by Forte40 @ GitHub (forked at v2.2.1)
--- Default configuration
--- All sides are used for peripheral.wrap calls. Can be proxied (check OpenPeripheral Proxy).
local configDefault = {
  ['storageProvider'] = 'openbee/StorageAE.lua', -- allows different storage backends
  ['breederProvider'] = 'openbee/BreederApiary.lua', -- allows different breeder backends
  ['beeBreedingData'] = 'openbee/BeeBreedingData.lua', -- allows different breeder backends
  ["analyzerDir"] = "west", -- direction from storage to analyzer
  ["storageDir"] = "south", -- direction from breeder to storage
  ["productDir"] = "down", -- direction from breeder to product storage
  ["breederDir"] = "north", -- direction from storage to breeder

  -- StorageAE block
  ['AE2MEInterfaceProbe'] = true, -- automatic probe for AE2 ME Interface
  -- ['AE2MEInterfaceSide'] = 'north', -- set here to skip probing and setup

  -- BreederApiary block
  ['apiaryProbe'] = true, -- automatic probe for Apiary
  -- ['apiarySide'] = 'north', -- set here to skip probing and setup

  -- Trait priorities block
  -- You probably down want to edit this, just supply them at runtime. Check README.md
  ["traitPriority"] = {
    "speciesChance",
    "speed",
    "fertility",
    "nocturnal",
    "tolerantFlyer",
    "temperatureTolerance",
    "humidityTolerance",
    "caveDwelling",
    "effect",
    "flowering",
    "flowerProvider",
    "territory"
  },

  -- FIXME old stuff, rewrite and remove
  ["ignoreSpecies"] = {
    "Leporine"
  },
  ["useAnalyzer"] = true,
  ["useReferenceBees"] = true -- try to keep 1 pure princess and 1 pure drone
}

--- Forte40 code with rewrites
-- All comments in this block below are original
Forte40 = {}
-- utility functions ------------------
function Forte40.choose(list1, list2)
  local newList = {}
  if list2 then
    for i = 1, #list2 do
      for j = 1, #list1 do
        if list1[j] ~= list2[i] then
          table.insert(newList, {list1[j], list2[i]})
        end
      end
    end
  else
    for i = 1, #list1 do
      for j = i, #list1 do
        if list1[i] ~= list1[j] then
          table.insert(newList, {list1[i], list1[j]})
        end
      end
    end
  end
  return newList
end
Forte40.nameFix = {}
-- fix for some versions returning bees.species.*
function Forte40.fixName(name)
  if type(name) == "table" then
    name = name.name
  end
  local newName = name:gsub("bees%.species%.",""):gsub("^.", string.upper)
  if name ~= newName then
    Forte40.nameFix[newName] = name
  end
  return newName
end
function Forte40.fixBee(bee)
  if bee.individual ~= nil then
    bee.individual.displayName = Forte40.fixName(bee.individual.displayName)
    if bee.individual.isAnalyzed then
      bee.individual.active.species.name = Forte40.fixName(bee.individual.active.species.name)
      bee.individual.inactive.species.name = Forte40.fixName(bee.individual.inactive.species.name)
    end
  end
  return bee
end
function Forte40.fixParents(parents)
  parents.allele1 = Forte40.fixName(parents.allele1)
  parents.allele2 = Forte40.fixName(parents.allele2)
  if parents.result then
    parents.result = Forte40.fixName(parents.result)
  end
  return parents
end
function Forte40.beeName(bee)
  if bee.individual.active then
    return bee.individual.active.species.name:sub(1,3) .. "-" ..
        bee.individual.inactive.species.name:sub(1,3)
  else
    return bee.individual.displayName:sub(1,3)
  end
end
-- mutations and scoring --------------
-- build mutation graph
function Forte40.buildMutationGraph(apiary)
  local mutations = {}
  function Forte40.addMutateTo(parent1, parent2, offspring, chance)
    if mutations[parent1] ~= nil then
      if mutations[parent1].mutateTo[offspring] ~= nil then
        mutations[parent1].mutateTo[offspring][parent2] = chance
      else
        mutations[parent1].mutateTo[offspring] = {[parent2] = chance}
      end
    else
      mutations[parent1] = {
        mutateTo = {[offspring]={[parent2] = chance}}
      }
    end
  end
  for _, parents in pairs(getBeeBreedingData()) do
    Forte40.fixParents(parents)
    Forte40.addMutateTo(parents.allele1, parents.allele2, parents.result, parents.chance)
    Forte40.addMutateTo(parents.allele2, parents.allele1, parents.result, parents.chance)
  end
  mutations.getBeeParents = function(name)
    return apiary.getBeeParents((Forte40.nameFix[name] or name))
  end
  return mutations
end
function Forte40.buildTargetSpeciesList(catalog, apiary)
  local targetSpeciesList = {}
  local parentss = apiary.peripheral.getBeeBreedingData()
  for _, parents in pairs(parentss) do
    local skip = false
    for i, ignoreSpecies in ipairs(config.registry.ignoreSpecies) do
      if parents.result == ignoreSpecies then
        skip = true
        break
      end
    end
    if not skip and
        (catalog.reference[parents.result] == nil or catalog.reference[parents.result].pair == nil) and  -- skip if reference pair exists
        catalog.reference[parents.allele1] ~= nil and catalog.reference[parents.allele2] ~= nil and
        ((catalog.reference[parents.allele1].princess ~= nil and catalog.reference[parents.allele2].drone ~= nil) or -- princess 1 and drone 2 available
        (catalog.reference[parents.allele2].princess ~= nil and catalog.reference[parents.allele1].drone ~= nil)) -- princess 2 and drone 1 available
    then
      table.insert(targetSpeciesList, parents.result)
    end
  end
  return targetSpeciesList
end
-- percent chance of 2 species turning into a target species
function Forte40.mutateSpeciesChance(mutations, species1, species2, targetSpecies)
  local chance = {}
  if species1 == species2 then
    chance[species1] = 100
  else
    chance[species1] = 50
    chance[species2] = 50
  end
  if mutations[species1] ~= nil then
    for species, mutates in pairs(mutations[species1].mutateTo) do
      local mutateChance = mutates[species2]
      if mutateChance ~= nil then
        chance[species] = mutateChance
        chance[species1] = chance[species1] - mutateChance / 2
        chance[species2] = chance[species2] - mutateChance / 2
      end
    end
  end
  return chance[targetSpecies] or 0.0
end
-- percent chance of 2 bees turning into target species
function Forte40.mutateBeeChance(mutations, princess, drone, targetSpecies)
  if princess.individual.isAnalyzed then
    if drone.individual.isAnalyzed then
      return (Forte40.mutateSpeciesChance(mutations, princess.individual.active.species.name, drone.individual.active.species.name, targetSpecies) / 4
          +Forte40.mutateSpeciesChance(mutations, princess.individual.inactive.species.name, drone.individual.active.species.name, targetSpecies) / 4
          +Forte40.mutateSpeciesChance(mutations, princess.individual.active.species.name, drone.individual.inactive.species.name, targetSpecies) / 4
          +Forte40.mutateSpeciesChance(mutations, princess.individual.inactive.species.name, drone.individual.inactive.species.name, targetSpecies) / 4)
    end
  elseif drone.individual.isAnalyzed then
  else
    return Forte40.mutateSpeciesChance(princess.individual.displayName, drone.individual.displayName, targetSpecies)
  end
end
function Forte40.buildScoring()
  local function makeNumberScorer(trait, default)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return (bee.individual.active[trait] + bee.individual.inactive[trait]) / 2
      else
        return default
      end
    end
    return scorer
  end

  local function makeBooleanScorer(trait)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return ((bee.individual.active[trait] and 1 or 0) + (bee.individual.inactive[trait] and 1 or 0)) / 2
      else
        return 0
      end
    end
    return scorer
  end

  local function makeTableScorer(trait, default, lookup)
    local function scorer(bee)
      if bee.individual.isAnalyzed then
        return ((lookup[bee.individual.active[trait]] or default) + (lookup[bee.individual.inactive[trait]] or default)) / 2
      else
        return default
      end
    end
    return scorer
  end

  local scoresTolerance = {
    ["None"]   = 0,
    ["Up 1"]   = 1,
    ["Up 2"]   = 2,
    ["Up 3"]   = 3,
    ["Up 4"]   = 4,
    ["Up 5"]   = 5,
    ["Down 1"] = 1,
    ["Down 2"] = 2,
    ["Down 3"] = 3,
    ["Down 4"] = 4,
    ["Down 5"] = 5,
    ["Both 1"] = 2,
    ["Both 2"] = 4,
    ["Both 3"] = 6,
    ["Both 4"] = 8,
    ["Both 5"] = 10
  }

  local scoresFlowerProvider = {
    ["None"] = 5,
    ["Rocks"] = 4,
    ["Flowers"] = 3,
    ["Mushroom"] = 2,
    ["Cacti"] = 1,
    ["Exotic Flowers"] = 0,
    ["Jungle"] = 0
  }

  return {
    ["fertility"] = makeNumberScorer("fertility", 1),
    ["flowering"] = makeNumberScorer("flowering", 1),
    ["speed"] = makeNumberScorer("speed", 1),
    ["lifespan"] = makeNumberScorer("lifespan", 1),
    ["nocturnal"] = makeBooleanScorer("nocturnal"),
    ["tolerantFlyer"] = makeBooleanScorer("tolerantFlyer"),
    ["caveDwelling"] = makeBooleanScorer("caveDwelling"),
    ["effect"] = makeBooleanScorer("effect"),
    ["temperatureTolerance"] = makeTableScorer("temperatureTolerance", 0, scoresTolerance),
    ["humidityTolerance"] = makeTableScorer("humidityTolerance", 0, scoresTolerance),
    ["flowerProvider"] = makeTableScorer("flowerProvider", 0, scoresFlowerProvider),
    ["territory"] = function(bee)
      if bee.individual.isAnalyzed then
        return ((bee.individual.active.territory[1] * bee.individual.active.territory[2] * bee.individual.active.territory[3]) +
            (bee.individual.inactive.territory[1] * bee.individual.inactive.territory[2] * bee.individual.inactive.territory[3])) / 2
      else
        return 0
      end
    end
  }
end
function Forte40.compareMates(a, b)
  for i, trait in ipairs(config.registry.traitPriority) do
    if a[trait] ~= b[trait] then
      return a[trait] > b[trait]
    end
  end
  return true
end
function Forte40.breedAllSpecies(mutations, interface, apiary, scorers, speciesList)
  if #speciesList == 0 then
    logger:log('< Forte40: Please add more bee species and press [Enter]')
    io.read("*l")
  else
    for i, targetSpecies in ipairs(speciesList) do
      Forte40.breedTargetSpecies(mutations, interface, apiary, scorers, targetSpecies)
    end
  end
end
function Forte40.breedBees(interface, apiary, princess, drone)
  apiary:clear()
  interface:putBee(princess.id, config.registry.breederDir, 1, 1)
  interface:putBee(drone.id, config.registry.breederDir, 1, 2)
  apiary:clear()
end
-- selects best pair for target species
--   or initiates breeding of lower species
function Forte40.selectPair(mutations, scorers, catalog, targetSpecies)
  logger:color(colors.gray):log('  Forte40: -> ' .. targetSpecies .. '\n'):color(colors.white)
  local baseChance = 0
  if #mutations.getBeeParents(targetSpecies) > 0 then
    local parents = mutations.getBeeParents(targetSpecies)[1]
    baseChance = parents.chance
    if table.getn(parents.specialConditions) > 0 then
      logger:log('  Forte40: special conditions:\n' .. table.concat(parents.specialConditions, '\n') .. '\n')
    end
  end
  local mateCombos = Forte40.choose(catalog.princesses, catalog.drones)
  local mates = {}
  local haveReference =
    catalog.reference[targetSpecies] ~= nil and
    catalog.reference[targetSpecies].princess ~= nil and
    catalog.reference[targetSpecies].drone ~= nil
  for i, v in ipairs(mateCombos) do
    local chance = Forte40.mutateBeeChance(mutations, v[1], v[2], targetSpecies) or 0
    if (not haveReference and chance >= baseChance / 2) or
            (haveReference and chance > 25) then
      local newMates = {
        ["princess"] = v[1],
        ["drone"] = v[2],
        ["speciesChance"] = chance
      }
      for trait, scorer in pairs(scorers) do
        newMates[trait] = (scorer(v[1]) + scorer(v[2])) / 2
      end
      table.insert(mates, newMates)
    end
  end
  if #mates > 0 then
    table.sort(mates, Forte40.compareMates)
    for i = math.min(#mates, 5), 2, -1 do
      local parents = mates[i]
      logger:debug('  Forte40: ' ..
              Forte40.beeName(parents.princess) .. ' ' ..
              Forte40.beeName(parents.drone) .. ' ' ..
              parents.speciesChance .. ' ' ..
              parents.fertility .. ' ' ..
              parents.flowering .. ' ' ..
              parents.nocturnal .. ' ' ..
              parents.tolerantFlyer .. ' ' ..
              parents.caveDwelling .. ' ' ..
              parents.lifespan .. ' ' ..
              parents.temperatureTolerance .. ' ' ..
              parents.humidityTolerance .. '\n')
    end
    local parents = mates[1]
    logger:log('  Forte40: best combination:\n' ..
            Forte40.beeName(parents.princess) .. ' ' ..
            Forte40.beeName(parents.drone) .. ' ' ..
            parents.speciesChance .. ' ' ..
            parents.fertility .. ' ' ..
            parents.flowering .. ' ' ..
            parents.nocturnal .. ' ' ..
            parents.tolerantFlyer .. ' ' ..
            parents.caveDwelling .. ' ' ..
            parents.lifespan .. ' ' ..
            parents.temperatureTolerance .. ' ' ..
            parents.humidityTolerance .. '\n')
    return mates[1]
  else
    -- check for reference bees and breed if drone count is 1
    if catalog.reference[targetSpecies] ~= nil and
       catalog.reference[targetSpecies].princess ~= nil and
       catalog.reference[targetSpecies].drone ~= nil
    then
      logger:log('  Forte40: Breeding extra drone from reference bees\n')
      return {
        ["princess"] = catalog.referencePrincessesBySpecies[targetSpecies],
        ["drone"] = catalog.referenceDronesBySpecies[targetSpecies]
      }
    end
    -- attempt lower tier bee
    local parentss = mutations.getBeeParents(targetSpecies)
    if #parentss > 0 then
      table.sort(parentss, function(a, b) return a.chance > b.chance end)
      local trySpecies = {}
      for i, parents in ipairs(parentss) do
        Forte40.fixParents(parents)
        if (catalog.reference[parents.allele2] == nil or
            catalog.reference[parents.allele2].pair == nil or -- no reference bee pair
            catalog.reference[parents.allele2].droneCount < 2 or -- no extra reference drone
            catalog.reference[parents.allele2].princess == nil) -- no converted princess
            and trySpecies[parents.allele2] == nil then
          table.insert(trySpecies, parents.allele2)
          trySpecies[parents.allele2] = true
        end
        if (catalog.reference[parents.allele1] == nil or
            catalog.reference[parents.allele1].pair == nil or -- no reference bee pair
            catalog.reference[parents.allele1].droneCount < 2 or -- no extra reference drone
            catalog.reference[parents.allele1].princess == nil) -- no converted princess
            and trySpecies[parents.allele1] == nil then
          table.insert(trySpecies, parents.allele1)
          trySpecies[parents.allele1] = true
        end
      end
      for _, species in ipairs(trySpecies) do
        local mates = Forte40.selectPair(mutations, scorers, catalog, species)
        if mates ~= nil then
          return mates
        end
      end
    end
    return nil
  end
end
function Forte40.isPureBred(bee1, bee2, targetSpecies)
  if bee1.individual.isAnalyzed and bee2.individual.isAnalyzed then
    if bee1.individual.active.species.name == bee1.individual.inactive.species.name and
            bee2.individual.active.species.name == bee2.individual.inactive.species.name and
            bee1.individual.active.species.name == bee2.individual.active.species.name and
            (targetSpecies == nil or bee1.individual.active.species.name == targetSpecies) then
      return true
    end
  elseif bee1.individual.isAnalyzed == false and bee2.individual.isAnalyzed == false then
    if bee1.individual.displayName == bee2.individual.displayName then
      return true
    end
  end
  return false
end
function Forte40.breedTargetSpecies(mutations, inv, apiary, scorers, targetSpecies)
  while true do
    if application.catalog.princessesCount == 0 then
      logger:color(colors.yellow)
            :log('< Forte40: Please add more princesses and press [Enter]')
            :color(colors.white)
      io.read("*l")
      application.catalog:run(application.storage)
    elseif application.catalog.dronesCount == 0 then
      logger:color(colors.yellow)
            :log('< Forte40: Please add more drones and press [Enter]')
            :color(colors.white)
      io.read("*l")
      application.catalog:run(application.storage)
    else
      logger:log('  Forte40: targetting ' .. targetSpecies .. '\n')
      local mates = Forte40.selectPair(mutations, scorers, application.catalog:toForte40(), targetSpecies)
      if mates ~= nil then
        if Forte40.isPureBred(mates.princess, mates.drone, targetSpecies) then
          break
        else
          Forte40.breedBees(inv, apiary, mates.princess, mates.drone)
          application.catalog:run(application.storage)
        end
      else
        logger:color(colors.yellow)
              :log('< Forte40: Please add more bee species for ' .. targetSpecies .. ' and press [Enter]')
              :color(colors.white)
        io.read("*l")
        application.catalog:run(application.storage)
      end
    end
  end
  logger:log('< Forte40: Bees are purebred\n')
end

--- Create table-based classes
-- @author http://lua-users.org/wiki/ObjectOrientationTutorial
function Creator(...)
  -- "cls" is the new class
  local cls, bases = {}, {...}
  -- copy base class contents into the new class
  for i, base in ipairs(bases) do
    for k, v in pairs(base) do
      cls[k] = v
    end
  end
  -- set the class's __index, and start filling an "is_a" table that contains this class and all of its bases
  -- so you can do an "instance of" check using my_instance.is_a[MyClass]
  cls.__index, cls.is_a = cls, {[cls] = true}
  for i, base in ipairs(bases) do
    for c in pairs(base.is_a) do
      cls.is_a[c] = true
    end
    cls.is_a[base] = true
  end
  -- the class's __call metamethod
  setmetatable(cls, {__call = function (c, ...)
    local instance = setmetatable({}, c)
    -- run the init method if it's there
    local init = instance._init
    if init then init(instance, ...) end
    return instance
  end})
  -- return the new class table, that's ready to fill with methods
  return cls
end

--- Application class
-- WOW, many OOP, such API, much methods
local App = Creator()
--- Provides most of initialization
function App:_init(args)
  self.version = '2.0.0'
  logger:color(colors.green)
        :log('> Second_Fry\'s openbee modular fork (v' .. self.version .. ')\n')
        :log('> Thanks to Forte40 @ GitHub (forked on v2.2.1)\n')
        :color(colors.gray)
        :log('  Got arguments: ' .. table.concat(args, ', ') .. '\n')
        :color(colors.white)
  fs.makeDir('.openbee')
  self.args = args or {}
  self.storage = self:initStorage()
  self.breeder = self:initBreeder()
  self.traitPriority = config.registry.traitPriority
  self:initMutationGraph()
  self.catalog = Catalog()
end
--- Iterates over requested species and traits and setups priorities
function App:parseArgs()
  local priority = 1
  local isTrait = false
  for _, marg in ipairs(self.args) do
    isTrait = false
    for priorityConfig = 1, #self.traitPriority do
      if marg == self.traitPriority[priorityConfig] then
        isTrait = true
        table.remove(self.traitPriority, priorityConfig)
        table.insert(self.traitPriority, priority, marg)
        priority = priority + 1
        break
      end
    end
    if not isTrait then
      self.speciesRequested = marg
    end
  end
end
function App:initStorage()
  local path = config.registry.storageProvider
  local filename = string.sub(path, 9) -- remove openbee/
  os.loadAPI(path)
  return _G[filename]['StorageProvider'](Creator, IStorage, config, logger, ItemTypes)()
end
function App:initBreeder()
  local path = config.registry.breederProvider
  local filename = string.sub(path, 9) -- remove openbee/
  os.loadAPI(path)
  return _G[filename]['BreederProvider'](Creator, IStorage, config, logger, ItemTypes)()
end
function App:initMutationGraph()
  self.beeGraph = {}
  local beeGraph = self.breeder.peripheral.getBeeBreedingData()
  for _, mutation in ipairs(beeGraph) do
    if self.beeGraph[mutation.result] == nil then self.beeGraph[mutation.result] = {} end
    table.insert(self.beeGraph[mutation.result], mutation)
    -- Somehow doesn't report Unusual as species via breeder.listAllSpecies()
    -- So using fix dirty fix
    BeeTypes[mutation.allele1] = true
    BeeTypes[mutation.allele2] = true
    BeeTypes[mutation.result] = true
  end
end
function App:analyzerClear()
  local beeID, beeTest, beeRet
  local residentSleeperTime = 0
  if not config.registry.useAnalyzer then return end
  self.storage:fetch()
  logger:log('    Analyzer: checking')
  while true do
    for slot = 9, 12 do self.storage.peripheral.pullItem(config.registry.analyzerDir, slot) end
    -- Check if Analyzer was operating
    -- This is not a cycle, runs once
    for id, bee in pairs(self.storage.bees) do
      if bee.individual.isAnalyzed then
        beeTest = bee
        beeID = id
      end
      break
    end
    if beeTest == nil then break else
      self.storage:putBee(beeID, config.registry.analyzerDir, 1, 8)
      sleep(1)
      residentSleeperTime = residentSleeperTime + 1
      beeRet = self.storage.peripheral.pullItem(config.registry.analyzerDir, 9)
      if beeRet > 0 then break else
        logger:clearLine():log('    Analyzer: waiting (' .. residentSleeperTime .. ' seconds)')
        sleep(5) -- Analyzer tick is 30 seconds
        residentSleeperTime = residentSleeperTime + 5
      end
    end
  end
  logger:clearLine():log('    Analyzer: done waiting (was ' .. residentSleeperTime .. ' seconds)\n')
end
function App:main()
  local doRestart = false
  logger:color(colors.lightBlue)
        :log('  Initial: clearing breeder\n')
        :color(colors.white)
  self.breeder:clear()
  logger:color(colors.lightBlue)
        :log('  Initial: clearing analyzer\n')
        :color(colors.white)
  self:analyzerClear()
  logger:color(colors.lightBlue)
        :log('  Initial: categorizing bees\n')
        :color(colors.white)
  self.catalog:run(self.storage)
  while self.catalog.queens ~= nil do
    logger:color(colors.lightBlue)
          :log('  Initial: clearing queens\n')
          :color(colors.white)
    for id, bee in pairs(self.catalog.queens) do
      self.storage:putBee(id, config.registry.breederDir)
      self.breeder:clear()
    end
    self.catalog:run(self.storage)
  end
  if self.speciesRequested ~= nil then
    self.speciesTarget = self.speciesRequested:sub(1,1):upper() .. self.speciesRequested:sub(2):lower()
    if BeeTypes[self.speciesTarget] ~= true then
      logger:color(colors.red)
            :log('! Species ' .. self.speciesTarget .. ' is not found!\n')
            :color(colors.white)
      return
    end
    Forte40.breedTargetSpecies(Forte40.buildMutationGraph(self.breeder.peripheral), self.storage, self.breeder, Forte40.buildScoring(), self.speciesTarget)
    -- FIXME use self:breedSpecies(self.speciesTarget)
  else -- FIXME implement self:breedAll()
    local mutations, scorers = Forte40.buildMutationGraph(self.breeder.peripheral), Forte40.buildScoring()
    while true do
      Forte40.breedAllSpecies(mutations, self.storage, self.breeder, scorers, Forte40.buildTargetSpeciesList(self.catalog, self.breeder))
      self.catalog:run(self.storage)
    end
  end
end
function App:analyze(id)
  local beeRet
  local residentSleeperTime = 32
  logger:log('    Analyze: some bee')
  self.storage:putBee(id, config.registry.analyzerDir, 64, 3) -- slot 3 is magic number
  sleep(32) -- Analyzer tick is 30 seconds
  while true do
    beeRet = 0
    for slot = 9, 12 do
      beeRet = beeRet + self.storage.peripheral.pullItem(config.registry.analyzerDir, slot)
    end
    if beeRet > 0 then break else
      logger:clearLine():log('    Analyze: waiting (' .. residentSleeperTime .. ' seconds)')
      sleep(5) -- Analyzer tick is 30 seconds
      residentSleeperTime = residentSleeperTime + 5
    end
  end
  logger:clearLine():log('    Analyze: done waiting (was ' .. residentSleeperTime .. ' seconds)\n')
end
function App:breedSpecies(species)
  logger:color(colors.lightBlue)
        :log('  Breeding: ' .. species .. '\n')
        :color(colors.white)
  while true do
    self.catalog:run(self.storage)
    if self.catalog.princesses == nil then
      logger:color(colors.yellow)
            :log('< Breeding: add more princesses?\n')
            :color(colors.white)
      io.read("*l")
    elseif self.catalog.drones == nil then
      logger:color(colors.yellow)
            :log('< Breeding: add more drones?\n')
            :color(colors.white)
      io.read("*l")
    else
      if self.beeGraph[species] ~= nil then
        self.parentBreedable = true
        -- TODO select parent line which exists (i.e. Common can be produced in tons of ways)
        for _, mutation in ipairs(self.beeGraph[species]) do
          for _, parent in ipairs({mutation.allele1, mutation.allele2}) do
            if self.catalog.reference[parent] == nil or
               self.catalog.reference[parent].drone == nil or
               self.catalog.reference[parent].droneCount < 2
            then
              logger:log('  Breeding: getting parent first\n')
              self:breedSpecies(parent)
            end
          end
        end
      else
        logger:color(colors.red)
              :log('  Breeder: can\'t breed prime species (' .. species .. ')')
              :color(colors.white)
        error('Prime ' .. species .. ' is not found.')
      end
      if table.getn(self.beeGraph[species].specialConditions) > 0 then
        logger:log('  Breeder: special conditions:\n' .. self.beeGraph[species].specialConditions:concat('\n'))
              :color(colors.yellow)
              :log('< Breeder: confirm that conditions met\n')
              :color(colors.white)
      end
      -- FIXME do some actual breeding
      break
    end
  end
  logger:log('  Breeding: untested done.\n')
end

--- Catalog class
Catalog = Creator()
function Catalog:run(storage)
  if config.registry.useAnalyzer == true then
    logger:color(colors.lightBlue)
          :log('  Catalog: analyzing bees\n')
          :color(colors.white)
    self:analyzeBees(storage)
  end
  logger:debug('  Catalog: creating\n')
  self:create(storage)
  logger:color(colors.lightBlue)
        :log('  Catalog: (TODO) building local mutation graph \n')
        :color(colors.white)
  self:buildMutationGraph(storage)
end
function Catalog:analyzeBees(storage)
  local analyzeCount = 0
  storage:fetch()
  for id, bee in pairs(storage.bees) do
    if not bee.individual.isAnalyzed then
      application:analyze(id)
      analyzeCount = analyzeCount + 1
    end
  end
  if analyzeCount > 0 then logger:log('    Catalog: analyzed ' .. analyzeCount .. ' new bees\n') end
end
function Catalog:create(storage)
  self.reference = {}
  self.drones = nil
  self.dronesCount = 0
  self.princesses = nil
  self.princessesCount = 0
  self.queens = nil
  storage:fetch()
  for id, bee in pairs(storage.bees) do
    local species = bee.individual.active.species.name
    if self.reference[species] == nil then self.reference[species] = {} end
    if ItemTypes[bee.id].isDrone then
      if self.reference[species].drone == nil then
        self.reference[species].drone = {}
        self.reference[species].droneCount = 0
      end
      if self.drones == nil then self.drones = {} end
      self.reference[species].drone[id] = bee
      self.reference[species].droneCount = self.reference[species].droneCount + bee.qty
      self.drones[id] = bee
      self.dronesCount = self.dronesCount + bee.qty
    end
    if ItemTypes[bee.id].isPrincess then
      if self.reference[species].princess == nil then
        self.reference[species].princess = {}
        self.reference[species].princessCount = 0
      end
      if self.princesses == nil then self.princesses = {} end
      self.reference[species].princess[id] = bee
      self.reference[species].princessCount = self.reference[species].princessCount + bee.qty
      self.princesses[id] = bee
      self.princessesCount = self.princessesCount + bee.qty
    end
    if ItemTypes[bee.id].isQueen then
      if self.queens == nil then self.queens = {} end
      self.queens[id] = bee
    end
    if self.reference[species].drone ~= nil and self.reference[species].princess ~= nil then
      self.reference[species].pair = true
    end
  end
  if table.getn(self.reference) > 0 then
    logger:log('    Catalog: have reference for:\n    ')
    for species, table in pairs(self.reference) do if table.pair == true then logger:log(species, ', ') end end
    logger:log('\n')
  end
end
function Catalog:buildMutationGraph()
  -- TODO implement local mutation graph using available bees
end
function Catalog:toForte40()
  local princessList, droneList = {}, {}
  if self.princesses ~= nil then for id, princess in pairs(self.princesses) do
    local proxy = princess
    proxy.id = id
    table.insert(princessList, proxy)
  end end
  if self.drones ~= nil then for id, drone in pairs(self.drones) do
    local proxy = drone
    proxy.id = id
    table.insert(droneList, proxy)
  end end
  return {
    ['princesses'] = princessList,
    ['drones'] = droneList,
    ['reference'] = self.reference
  }
end

--- Breeder classes interface
IBreeder = Creator()
--- Initalizes breeder
-- Stores wrapped peripheral in peripheral attribute
-- @return IBreeder instance for chaining
function IBreeder:_init()
  return self
end
--- Clears the breeder
-- Bees should land into storage system (doesn't matter if analyzed or not)
-- @return IBreeder instance for chaining
function IBreeder:clear()
  return self
end

--- Storage classes interface
IStorage = Creator()
--- Initalizes storage
-- Stores wrapped peripheral in peripheral attribute
-- @return IStorage instance for chaining
function IStorage:_init()
  return self
end
--- Gets all and only bees from storage
-- @return IStorage instance for chaining
function IStorage:fetch()
  return self
end
--- Returns all bess from storage
function IStorage:getBees()
  return IStorage:fetch().bees
end
--- Puts bee somewhere
-- @param id ID for bee
-- @param peripheralSide Side where to push
-- @return IStorage instance for chaining
function IStorage:putBee(id, peripheralSide)
  return self
end

--- Item ids for bees
ItemTypes = {
  ['Forestry:beeDroneGE'] = {
    ['isBee'] = true,
    ['isDrone'] = true
  },
  ['Forestry:beePrincessGE'] = {
    ['isBee'] = true,
    ['isPrincess'] = true
  },
  ['Forestry:beeQueenGE'] = {
    ['isBee'] = true,
    ['isQueen'] = true
  },
}
BeeTypes = {}

--- Configuration class
Config = Creator()
function Config:_init(filename)
  self.file = File(filename)
  self.registry = self.file:read()
  if self.registry == nil then
    self.registry = configDefault
    self.file:write(self.registry)
  end
  return self
end

--- Logging class
Log = Creator()
function Log:_init()
  fs.makeDir('.openbee/logs')
  local loglast = table.remove(natsort(fs.list('.openbee/logs')))
  if loglast == nil then
    self.lognum = 1
  else
    self.lognum = tonumber(string.sub(loglast, 5)) + 1
  end
  self.logname = '.openbee/logs/log-' .. string.format("%03d", self.lognum)
  self.logfile = File(self.logname)
  self.logfile:open('w')
end
function Log:log(...)
  self:debug(arg)
  for _, marg in ipairs(arg) do
    if type(marg) == "table" then
      io.write(table.concat(marg, ' '))
    else
      io.write(marg)
    end
  end
  return self
end
function Log:debug(...)
  for _, marg in ipairs(arg) do
    if type(marg) == "table" then
      self.logfile:append(table.concat(marg, ' '))
    else
      self.logfile:append(marg)
    end
  end
  return self
end
function Log:color(color)
  term.setTextColor(color)
  return self
end
function Log:clearLine()
  local x, y = term.getCursorPos()
  term.clearLine()
  term.setCursorPos(1, y)
  return self
end
function Log:finish()
  self:color(colors.green)
      :log('> Successful finish (' .. self.logname .. ')\n')
  self.logfile:close()
end

--- File class
File = Creator()
function File:_init(filename)
  self.filename = filename
  return self
end
function File:open(mode)
  self.file = fs.open(self.filename, mode)
  return self
end
function File:read()
  self:open('r')
  if self.file ~= nil then
    local data = self.file.readAll()
    self:close()
    return textutils.unserialize(data)
  end
end
function File:write(data)
  self:open('w').file.write(textutils.serialize(data))
  self:close()
end
function File:append(data)
  self.file.write(data)
end
function File:close()
  self.file.close()
end

--- natsort
function natsort(o)
  local function padnum(d) return ("%012d"):format(d) end
  table.sort(o, function(a,b)
    return tostring(a):gsub("%d+",padnum) < tostring(b):gsub("%d+",padnum) end)
  return o
end

--BeeBreedingData
function getBeeBreedingData()
  breedingTable = {}
  breedingTable[1] = {
    ['allele1'] = "Forest",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[2] = {
    ['allele1'] = "Modest",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[3] = {
    ['allele1'] = "Modest",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[4] = {
    ['allele1'] = "Wintry",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[5] = {
    ['allele1'] = "Wintry",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[6] = {
    ['allele1'] = "Wintry",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[7] = {
    ['allele1'] = "Tropical",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[8] = {
    ['allele1'] = "Tropical",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[9] = {
    ['allele1'] = "Tropical",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Common",
    ['chance'] = 15
  }
  breedingTable[10] = {
    ['allele1'] = "Tropical",
    ['specialConditions'] = {},
    ['allele2'] = "Wintry",
    ['result'] = "Common",
    ['chance'] = 15
   }
  breedingTable[11] = {
    ['allele1'] = "Marshy",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Common",
    ['chance'] = 15
   }
  breedingTable[12] = {
    ['allele1'] = "Marshy",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Common",
    ['chance'] = 15
   }
  breedingTable[13] = {
    ['allele1'] = "Marshy",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Common",
    ['chance'] = 15
   }
  breedingTable[14] = {
    ['allele1'] = "Marshy",
    ['specialConditions'] = {},
    ['allele2'] = "Wintry",
    ['result'] = "Common",
    ['chance'] = 15
   }
  breedingTable[15] = {
    ['allele1'] = "Marshy",
    ['specialConditions'] = {},
    ['allele2'] = "Tropical",
    ['result'] = "Common",
    ['chance'] = 15
   }
  breedingTable[16] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Cultivated",
    ['chance'] = 12
   }
  breedingTable[17] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Cultivated",
    ['chance'] = 12
   }
  breedingTable[18] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Cultivated",
    ['chance'] = 12
   }
  breedingTable[19] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Wintry",
    ['result'] = "Cultivated",
    ['chance'] = 12
   }
  breedingTable[20] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Tropical",
    ['result'] = "Cultivated",
    ['chance'] = 12
   }
  breedingTable[21] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Marshy",
    ['result'] = "Cultivated",
    ['chance'] = 12
   }
  breedingTable[22] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Cultivated",
    ['result'] = "Noble",
    ['chance'] = 10
   }
  breedingTable[23] = {
    ['allele1'] = "Noble",
    ['specialConditions'] = {},
    ['allele2'] = "Cultivated",
    ['result'] = "Majestic",
    ['chance'] = 8
   }
  breedingTable[24] = {
    ['allele1'] = "Noble",
    ['specialConditions'] = {},
    ['allele2'] = "Majestic",
    ['result'] = "Imperial",
    ['chance'] = 8
   }
  breedingTable[25] = {
    ['allele1'] = "Common",
    ['specialConditions'] = {},
    ['allele2'] = "Cultivated",
    ['result'] = "Diligent",
    ['chance'] = 10
   }
  breedingTable[26] = {
    ['allele1'] = "Diligent",
    ['specialConditions'] = {},
    ['allele2'] = "Cultivated",
    ['result'] = "Unweary",
    ['chance'] = 8
   }
  breedingTable[27] = {
    ['allele1'] = "Diligent",
    ['specialConditions'] = {},
    ['allele2'] = "Unweary",
    ['result'] = "Industrious",
    ['chance'] = 8
   }
  breedingTable[28] = {
    ['allele1'] = "Steadfast",
    ['specialConditions'] = {[1] = "Is restricted to FOREST-like environments."},
    ['allele2'] = "Valiant",
    ['result'] = "Heroic",
    ['chance'] = 6
   }
  breedingTable[29] = {
    ['allele1'] = "Modest",
    ['specialConditions'] = {[1] = "Is restricted to NETHER-like environments."},
    ['allele2'] = "Cultivated",
    ['result'] = "Sinister",
    ['chance'] = 60
   }
  breedingTable[30] = {
    ['allele1'] = "Tropical",
    ['specialConditions'] = {},
    ['allele2'] = "Cultivated",
    ['result'] = "Sinister",
    ['chance'] = 60
   }
  breedingTable[31] = {
    ['allele1'] = "Sinister",
    ['specialConditions'] = {},
    ['allele2'] = "Cultivated",
    ['result'] = "Fiendish",
    ['chance'] = 40
   }
  breedingTable[32] = {
    ['allele1'] = "Sinister",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Fiendish",
    ['chance'] = 40
   }
  breedingTable[33] = {
    ['allele1'] = "Sinister",
    ['specialConditions'] = {},
    ['allele2'] = "Tropical",
    ['result'] = "Fiendish",
    ['chance'] = 40
   }
  breedingTable[34] = {
    ['allele1'] = "Sinister",
    ['specialConditions'] = {},
    ['allele2'] = "Fiendish",
    ['result'] = "Demonic",
    ['chance'] = 25
   }
  breedingTable[35] = {
    ['allele1'] = "Modest",
    ['specialConditions'] = {
      [1] = "Temperature between WARM and HOT.",
      [2] = "Humidity ARID required.",
      },
    ['allele2'] = "Sinister",
    ['result'] = "Frugal",
    ['chance'] = 16
   }
  breedingTable[36] = {
    ['allele1'] = "Modest",
    ['specialConditions'] = {},
    ['allele2'] = "Fiendish",
    ['result'] = "Frugal",
    ['chance'] = 10
   }
  breedingTable[37] = {
    ['allele1'] = "Modest",
    ['specialConditions'] = {},
    ['allele2'] = "Frugal",
    ['result'] = "Austere",
    ['chance'] = 8
   }
  breedingTable[38] = {
    ['allele1'] = "Austere",
    ['specialConditions'] = {},
    ['allele2'] = "Tropical",
    ['result'] = "Exotic",
    ['chance'] = 12
   }
  breedingTable[39] = {
    ['allele1'] = "Exotic",
    ['specialConditions'] = {},
    ['allele2'] = "Tropical",
    ['result'] = "Edenic",
    ['chance'] = 8
   }
  breedingTable[40] = {
    ['allele1'] = "Industrious",
    ['specialConditions'] = {[1] = "Temperature between ICY and COLD."},
    ['allele2'] = "Wintry",
    ['result'] = "Icy",
    ['chance'] = 12
   }
  breedingTable[41] = {
    ['allele1'] = "Icy",
    ['specialConditions'] = {},
    ['allele2'] = "Wintry",
    ['result'] = "Glacial",
    ['chance'] = 8
   }
  breedingTable[42] = {
    ['allele1'] = "Meadows",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Leporine",
    ['chance'] = 10
   }
  breedingTable[43] = {
    ['allele1'] = "Wintry",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Merry",
    ['chance'] = 10
   }
  breedingTable[44] = {
    ['allele1'] = "Wintry",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Tipsy",
    ['chance'] = 10
   }
  breedingTable[45] = {
    ['allele1'] = "Sinister",
    ['specialConditions'] = {},
    ['allele2'] = "Common",
    ['result'] = "Tricky",
    ['chance'] = 10
   }
  breedingTable[46] = {
    ['allele1'] = "Meadows",
    ['specialConditions'] = {[1] = "Is restricted to PLAINS-like environments."},
    ['allele2'] = "Diligent",
    ['result'] = "Rural",
    ['chance'] = 12
   }
  breedingTable[47] = {
    ['allele1'] = "Monastic",
    ['specialConditions'] = {},
    ['allele2'] = "Austere",
    ['result'] = "Secluded",
    ['chance'] = 12
   }
  breedingTable[48] = {
    ['allele1'] = "Monastic",
    ['specialConditions'] = {},
    ['allele2'] = "Secluded",
    ['result'] = "Hermitic",
    ['chance'] = 8
   }
  breedingTable[49] = {
    ['allele1'] = "Hermitic",
    ['specialConditions'] = {},
    ['allele2'] = "Ender",
    ['result'] = "Spectral",
    ['chance'] = 4
   }
  breedingTable[50] = {
    ['allele1'] = "Spectral",
    ['specialConditions'] = {},
    ['allele2'] = "Ender",
    ['result'] = "Phantasmal",
    ['chance'] = 2
   }
  breedingTable[51] = {
    ['allele1'] = "Monastic",
    ['specialConditions'] = {},
    ['allele2'] = "Demonic",
    ['result'] = "Vindictive",
    ['chance'] = 4
   }
  breedingTable[52] = {
    ['allele1'] = "Demonic",
    ['specialConditions'] = {},
    ['allele2'] = "Vindictive",
    ['result'] = "Vengeful",
    ['chance'] = 8
   }
  breedingTable[53] = {
    ['allele1'] = "Monastic",
    ['specialConditions'] = {},
    ['allele2'] = "Vindictive",
    ['result'] = "Vengeful",
    ['chance'] = 8
   }
  breedingTable[54] = {
    ['allele1'] = "Vengeful",
    ['specialConditions'] = {},
    ['allele2'] = "Vindictive",
    ['result'] = "Avenging",
    ['chance'] = 4
   }
  breedingTable[55] = {
    ['allele1'] = "Meadows",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Arid",
    ['chance'] = 10
   }
  breedingTable[56] = {
    ['allele1'] = "Arid",
    ['specialConditions'] = {},
    ['allele2'] = "Common",
    ['result'] = "Barren",
    ['chance'] = 8
   }
  breedingTable[57] = {
    ['allele1'] = "Arid",
    ['specialConditions'] = {},
    ['allele2'] = "Barren",
    ['result'] = "Desolate",
    ['chance'] = 8
   }
  breedingTable[58] = {
    ['allele1'] = "Barren",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Gnawing",
    ['chance'] = 15
   }
  breedingTable[59] = {
    ['allele1'] = "Desolate",
    ['specialConditions'] = {},
    ['allele2'] = "Modest",
    ['result'] = "Decaying",
    ['chance'] = 15
   }
  breedingTable[60] = {
    ['allele1'] = "Desolate",
    ['specialConditions'] = {},
    ['allele2'] = "Frugal",
    ['result'] = "Skeletal",
    ['chance'] = 15
   }
  breedingTable[61] = {
    ['allele1'] = "Desolate",
    ['specialConditions'] = {},
    ['allele2'] = "Austere",
    ['result'] = "Creepy",
    ['chance'] = 15
   }
  breedingTable[62] = {
    ['allele1'] = "Gnawing",
    ['specialConditions'] = {},
    ['allele2'] = "Common",
    ['result'] = "Decomposing",
    ['chance'] = 15
   }
  breedingTable[63] = {
    ['allele1'] = "Rocky",
    ['specialConditions'] = {},
    ['allele2'] = "Diligent",
    ['result'] = "Tolerant",
    ['chance'] = 15
   }
  breedingTable[64] = {
    ['allele1'] = "Rocky",
    ['specialConditions'] = {},
    ['allele2'] = "Tolerant",
    ['result'] = "Robust",
    ['chance'] = 15
   }
  breedingTable[65] = {
    ['allele1'] = "Imperial",
    ['specialConditions'] = {},
    ['allele2'] = "Robust",
    ['result'] = "Resilient",
    ['chance'] = 15
   }
  breedingTable[66] = {
    ['allele1'] = "Resilient",
    ['specialConditions'] = {},
    ['allele2'] = "Meadows",
    ['result'] = "Rusty",
    ['chance'] = 5
   }
  breedingTable[67] = {
    ['allele1'] = "Resilient",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Corroded",
    ['chance'] = 5
   }
  breedingTable[68] = {
    ['allele1'] = "Resilient",
    ['specialConditions'] = {},
    ['allele2'] = "Marshy",
    ['result'] = "Tarnished",
    ['chance'] = 5
   }
  breedingTable[69] = {
    ['allele1'] = "Resilient",
    ['specialConditions'] = {},
    ['allele2'] = "Unweary",
    ['result'] = "Leaden",
    ['chance'] = 5
   }
  breedingTable[70] = {
    ['allele1'] = "Resilient",
    ['specialConditions'] = {},
    ['allele2'] = "Unweary",
    ['result'] = "Lustered",
    ['chance'] = 10
   }
  breedingTable[71] = {
    ['allele1'] = "Rusty",
    ['specialConditions'] = {},
    ['allele2'] = "Imperial",
    ['result'] = "Shining",
    ['chance'] = 2
   }
  breedingTable[72] = {
    ['allele1'] = "Corroded",
    ['specialConditions'] = {},
    ['allele2'] = "Imperial",
    ['result'] = "Glittering",
    ['chance'] = 2
   }
  breedingTable[73] = {
    ['allele1'] = "Glittering",
    ['specialConditions'] = {},
    ['allele2'] = "Shining",
    ['result'] = "Valuable",
    ['chance'] = 2
   }
  breedingTable[74] = {
    ['allele1'] = "Resilient",
    ['specialConditions'] = {},
    ['allele2'] = "Water",
    ['result'] = "Lapis",
    ['chance'] = 5
   }
  breedingTable[75] = {
    ['allele1'] = "Lapis",
    ['specialConditions'] = {},
    ['allele2'] = "Noble",
    ['result'] = "Emerald",
    ['chance'] = 5
   }
  breedingTable[76] = {
    ['allele1'] = "Emerald",
    ['specialConditions'] = {},
    ['allele2'] = "Austere",
    ['result'] = "Ruby",
    ['chance'] = 5
   }
  breedingTable[77] = {
    ['allele1'] = "Emerald",
    ['specialConditions'] = {},
    ['allele2'] = "Ocean",
    ['result'] = "Sapphire",
    ['chance'] = 5
   }
  breedingTable[78] = {
    ['allele1'] = "Lapis",
    ['specialConditions'] = {},
    ['allele2'] = "Imperial",
    ['result'] = "Diamond",
    ['chance'] = 5
   }
  breedingTable[79] = {
    ['allele1'] = "Austere",
    ['specialConditions'] = {},
    ['allele2'] = "Rocky",
    ['result'] = "Unstable",
    ['chance'] = 5
   }
  breedingTable[80] = {
    ['allele1'] = "Unstable",
    ['specialConditions'] = {},
    ['allele2'] = "Rusty",
    ['result'] = "Nuclear",
    ['chance'] = 5
   }
  breedingTable[81] = {
    ['allele1'] = "Nuclear",
    ['specialConditions'] = {},
    ['allele2'] = "Glittering",
    ['result'] = "Radioactive",
    ['chance'] = 5
   }
  breedingTable[82] = {
    ['allele1'] = "Noble",
    ['specialConditions'] = {},
    ['allele2'] = "Diligent",
    ['result'] = "Ancient",
    ['chance'] = 10
   }
  breedingTable[83] = {
    ['allele1'] = "Ancient",
    ['specialConditions'] = {},
    ['allele2'] = "Noble",
    ['result'] = "Primeval",
    ['chance'] = 8
   }
  breedingTable[84] = {
    ['allele1'] = "Primeval",
    ['specialConditions'] = {},
    ['allele2'] = "Majestic",
    ['result'] = "Prehistoric",
    ['chance'] = 8
   }
  breedingTable[85] = {
    ['allele1'] = "Prehistoric",
    ['specialConditions'] = {},
    ['allele2'] = "Imperial",
    ['result'] = "Relic",
    ['chance'] = 8
   }
  breedingTable[86] = {
    ['allele1'] = "Primeval",
    ['specialConditions'] = {},
    ['allele2'] = "Growing",
    ['result'] = "Fossilised",
    ['chance'] = 8
   }
  breedingTable[87] = {
    ['allele1'] = "Primeval",
    ['specialConditions'] = {},
    ['allele2'] = "Fungal",
    ['result'] = "Resinous",
    ['chance'] = 8
   }
  breedingTable[88] = {
    ['allele1'] = "Primeval",
    ['specialConditions'] = {},
    ['allele2'] = "Ocean",
    ['result'] = "Oily",
    ['chance'] = 8
   }
  breedingTable[89] = {
    ['allele1'] = "Primeval",
    ['specialConditions'] = {},
    ['allele2'] = "Boggy",
    ['result'] = "Preserved",
    ['chance'] = 8
   }
  breedingTable[90] = {
    ['allele1'] = "Oily",
    ['specialConditions'] = {},
    ['allele2'] = "Industrious",
    ['result'] = "Distilled",
    ['chance'] = 8
   }
  breedingTable[91] = {
    ['allele1'] = "Oily",
    ['specialConditions'] = {},
    ['allele2'] = "Distilled",
    ['result'] = "Refined",
    ['chance'] = 8
   }
  breedingTable[92] = {
    ['allele1'] = "Refined",
    ['specialConditions'] = {},
    ['allele2'] = "Fossilised",
    ['result'] = "Tarry",
    ['chance'] = 8
   }
  breedingTable[93] = {
    ['allele1'] = "Refined",
    ['specialConditions'] = {},
    ['allele2'] = "Resinous",
    ['result'] = "Elastic",
    ['chance'] = 8
   }
  breedingTable[94] = {
    ['allele1'] = "Water",
    ['specialConditions'] = {},
    ['allele2'] = "Common",
    ['result'] = "River",
    ['chance'] = 10
   }
  breedingTable[95] = {
    ['allele1'] = "Water",
    ['specialConditions'] = {
[1] = "Hive needs to be in Ocean",
                            },
    ['allele2'] = "Diligent",
    ['result'] = "Ocean",
    ['chance'] = 10
   }
  breedingTable[96] = {
    ['allele1'] = "Ebony",
    ['specialConditions'] = {},
    ['allele2'] = "Ocean",
    ['result'] = "Stained",
    ['chance'] = 8
   }
  breedingTable[97] = {
    ['allele1'] = "Diligent",
    ['specialConditions'] = {},
    ['allele2'] = "Forest",
    ['result'] = "Growing",
    ['chance'] = 10
   }
  breedingTable[98] = {
    ['allele1'] = "Growing",
    ['specialConditions'] = {},
    ['allele2'] = "Rural",
    ['result'] = "Thriving",
    ['chance'] = 10
   }
  breedingTable[99] = {
    ['allele1'] = "Thriving",
    ['specialConditions'] = {},
    ['allele2'] = "Growing",
    ['result'] = "Blooming",
    ['chance'] = 8
   }
  breedingTable[100] = {
     ['allele1'] = "Valiant",
     ['specialConditions'] = {},
     ['allele2'] = "Diligent",
     ['result'] = "Sweetened",
     ['chance'] = 15
    }
  breedingTable[101] = {
     ['allele1'] = "Sweetened",
     ['specialConditions'] = {},
     ['allele2'] = "Diligent",
     ['result'] = "Sugary",
     ['chance'] = 15
    }
  breedingTable[102] = {
     ['allele1'] = "Sugary",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Ripening",
     ['chance'] = 5
    }
  breedingTable[103] = {
     ['allele1'] = "Ripening",
     ['specialConditions'] = {},
     ['allele2'] = "Rural",
     ['result'] = "Fruity",
     ['chance'] = 5
    }
  breedingTable[104] = {
     ['allele1'] = "Cultivated",
     ['specialConditions'] = {},
     ['allele2'] = "Rural",
     ['result'] = "Farmed",
     ['chance'] = 10
    }
  breedingTable[105] = {
     ['allele1'] = "Rural",
     ['specialConditions'] = {},
     ['allele2'] = "Water",
     ['result'] = "Bovine",
     ['chance'] = 10
    }
  breedingTable[106] = {
     ['allele1'] = "Tropical",
     ['specialConditions'] = {},
     ['allele2'] = "Rural",
     ['result'] = "Caffeinated",
     ['chance'] = 10
    }
  breedingTable[107] = {
     ['allele1'] = "Common",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Damp",
     ['chance'] = 10
    }
  breedingTable[108] = {
     ['allele1'] = "Damp",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Boggy",
     ['chance'] = 8
    }
  breedingTable[109] = {
     ['allele1'] = "Boggy",
     ['specialConditions'] = {},
     ['allele2'] = "Damp",
     ['result'] = "Fungal",
     ['chance'] = 8
    }
  breedingTable[110] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[111] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Meadows",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[112] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Modest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[113] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[114] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[115] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[116] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Rocky",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[117] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[118] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[119] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Meadows",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[120] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Modest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[121] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[122] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[123] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[124] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[125] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Common",
     ['result'] = "Cultivated",
     ['chance'] = 12
    }
  breedingTable[126] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Common",
     ['result'] = "Cultivated",
     ['chance'] = 12
    }
  breedingTable[127] = {
     ['allele1'] = "Embittered",
     ['specialConditions'] = {},
     ['allele2'] = "Sinister",
     ['result'] = "Furious",
     ['chance'] = 10
    }
  breedingTable[128] = {
     ['allele1'] = "Embittered",
     ['specialConditions'] = {},
     ['allele2'] = "Furious",
     ['result'] = "Volcanic",
     ['chance'] = 6
    }
  breedingTable[129] = {
     ['allele1'] = "Sinister",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Malicious",
     ['chance'] = 10
    }
  breedingTable[130] = {
     ['allele1'] = "Malicious",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Infectious",
     ['chance'] = 8
    }
  breedingTable[131] = {
     ['allele1'] = "Malicious",
     ['specialConditions'] = {},
     ['allele2'] = "Infectious",
     ['result'] = "Virulent",
     ['chance'] = 8
    }
  breedingTable[132] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Exotic",
     ['result'] = "Viscous",
     ['chance'] = 10
    }
  breedingTable[133] = {
     ['allele1'] = "Viscous",
     ['specialConditions'] = {},
     ['allele2'] = "Exotic",
     ['result'] = "Glutinous",
     ['chance'] = 8
    }
  breedingTable[134] = {
     ['allele1'] = "Viscous",
     ['specialConditions'] = {},
     ['allele2'] = "Glutinous",
     ['result'] = "Sticky",
     ['chance'] = 8
    }
  breedingTable[135] = {
     ['allele1'] = "Virulent",
     ['specialConditions'] = {},
     ['allele2'] = "Sticky",
     ['result'] = "Corrosive",
     ['chance'] = 10
    }
  breedingTable[136] = {
     ['allele1'] = "Corrosive",
     ['specialConditions'] = {},
     ['allele2'] = "Fiendish",
     ['result'] = "Caustic",
     ['chance'] = 8
    }
  breedingTable[137] = {
     ['allele1'] = "Corrosive",
     ['specialConditions'] = {},
     ['allele2'] = "Caustic",
     ['result'] = "Acidic",
     ['chance'] = 4
    }
  breedingTable[138] = {
     ['allele1'] = "Cultivated",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Excited",
     ['chance'] = 10
    }
  breedingTable[139] = {
     ['allele1'] = "Excited",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Energetic",
     ['chance'] = 8
    }
  breedingTable[140] = {
     ['allele1'] = "Wintry",
     ['specialConditions'] = {},
     ['allele2'] = "Diligent",
     ['result'] = "Frigid",
     ['chance'] = 10
    }
  breedingTable[141] = {
     ['allele1'] = "Ocean",
     ['specialConditions'] = {},
     ['allele2'] = "Frigid",
     ['result'] = "Absolute",
     ['chance'] = 10
    }
  breedingTable[142] = {
     ['allele1'] = "Tolerant",
     ['specialConditions'] = {},
     ['allele2'] = "Sinister",
     ['result'] = "Shadowed",
     ['chance'] = 10
    }
  breedingTable[143] = {
     ['allele1'] = "Shadowed",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Darkened",
     ['chance'] = 8
    }
  breedingTable[144] = {
     ['allele1'] = "Shadowed",
     ['specialConditions'] = {},
     ['allele2'] = "Darkened",
     ['result'] = "Abyssal",
     ['chance'] = 8
    }
  breedingTable[145] = {
     ['allele1'] = "Forest",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Maroon",
     ['chance'] = 5
    }
  breedingTable[146] = {
     ['allele1'] = "Meadows",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Saffron",
     ['chance'] = 5
    }
  breedingTable[147] = {
     ['allele1'] = "Water",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Prussian",
     ['chance'] = 5
    }
  breedingTable[148] = {
     ['allele1'] = "Tropical",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Natural",
     ['chance'] = 5
    }
  breedingTable[149] = {
     ['allele1'] = "Rocky",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Ebony",
     ['chance'] = 5
    }
  breedingTable[150] = {
     ['allele1'] = "Wintry",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Bleached",
     ['chance'] = 5
    }
  breedingTable[151] = {
     ['allele1'] = "Marshy",
     ['specialConditions'] = {},
     ['allele2'] = "Valiant",
     ['result'] = "Sepia",
     ['chance'] = 5
    }
  breedingTable[152] = {
     ['allele1'] = "Maroon",
     ['specialConditions'] = {},
     ['allele2'] = "Saffron",
     ['result'] = "Amber",
     ['chance'] = 5
    }
  breedingTable[153] = {
     ['allele1'] = "Natural",
     ['specialConditions'] = {},
     ['allele2'] = "Prussian",
     ['result'] = "Turquoise",
     ['chance'] = 5
    }
  breedingTable[154] = {
     ['allele1'] = "Maroon",
     ['specialConditions'] = {},
     ['allele2'] = "Prussian",
     ['result'] = "Indigo",
     ['chance'] = 5
    }
  breedingTable[155] = {
     ['allele1'] = "Ebony",
     ['specialConditions'] = {},
     ['allele2'] = "Bleached",
     ['result'] = "Slate",
     ['chance'] = 5
    }
  breedingTable[156] = {
     ['allele1'] = "Prussian",
     ['specialConditions'] = {},
     ['allele2'] = "Bleached",
     ['result'] = "Azure",
     ['chance'] = 5
    }
  breedingTable[157] = {
     ['allele1'] = "Maroon",
     ['specialConditions'] = {},
     ['allele2'] = "Bleached",
     ['result'] = "Lavender",
     ['chance'] = 5
    }
  breedingTable[158] = {
     ['allele1'] = "Natural",
     ['specialConditions'] = {},
     ['allele2'] = "Bleached",
     ['result'] = "Lime",
     ['chance'] = 5
    }
  breedingTable[159] = {
     ['allele1'] = "Indigo",
     ['specialConditions'] = {},
     ['allele2'] = "Lavender",
     ['result'] = "Fuchsia",
     ['chance'] = 5
    }
  breedingTable[160] = {
     ['allele1'] = "Slate",
     ['specialConditions'] = {},
     ['allele2'] = "Bleached",
     ['result'] = "Ashen",
     ['chance'] = 5
    }
  breedingTable[161] = {
     ['allele1'] = "Furious",
     ['specialConditions'] = {},
     ['allele2'] = "Excited",
     ['result'] = "Glowering",
     ['chance'] = 5
    }
  breedingTable[162] = {
     ['allele1'] = "Austere",
     ['specialConditions'] = {},
     ['allele2'] = "Desolate",
     ['result'] = "Hazardous",
     ['chance'] = 5
    }
  breedingTable[163] = {
     ['allele1'] = "Ender",
     ['specialConditions'] = {},
     ['allele2'] = "Relic",
     ['result'] = "Jaded",
     ['chance'] = 2
    }
  breedingTable[164] = {
     ['allele1'] = "Austere",
     ['specialConditions'] = {},
     ['allele2'] = "Excited",
     ['result'] = "Celebratory",
     ['chance'] = 5
    }
  breedingTable[165] = {
     ['allele1'] = "Secluded",
     ['specialConditions'] = {},
     ['allele2'] = "Ender",
     ['result'] = "Abnormal",
     ['chance'] = 5
    }
  breedingTable[166] = {
     ['allele1'] = "Abnormal",
     ['specialConditions'] = {},
     ['allele2'] = "Hermitic",
     ['result'] = "Spatial",
     ['chance'] = 5
    }
  breedingTable[167] = {
     ['allele1'] = "Spatial",
     ['specialConditions'] = {},
     ['allele2'] = "Spectral",
     ['result'] = "Quantum",
     ['chance'] = 5
    }
  breedingTable[168] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[169] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Meadows",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[170] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Modest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[171] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[172] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[173] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[174] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Rocky",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[175] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Water",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[176] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[177] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Common",
     ['result'] = "Cultivated",
     ['chance'] = 12
    }
  breedingTable[178] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Cultivated",
     ['result'] = "Eldritch",
     ['chance'] = 12
    }
  breedingTable[179] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[180] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Meadows",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[181] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Modest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[182] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[183] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[184] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[185] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Rocky",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[186] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Water",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[187] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[188] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Common",
     ['result'] = "Cultivated",
     ['chance'] = 12
    }
  breedingTable[189] = {
     ['allele1'] = "Sorcerous",
     ['specialConditions'] = {},
     ['allele2'] = "Cultivated",
     ['result'] = "Eldritch",
     ['chance'] = 12
    }
  breedingTable[190] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[191] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Meadows",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[192] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Modest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[193] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[194] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[195] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[196] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Rocky",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[197] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Water",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[198] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[199] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Common",
     ['result'] = "Cultivated",
     ['chance'] = 12
    }
  breedingTable[200] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Cultivated",
     ['result'] = "Eldritch",
     ['chance'] = 12
    }
  breedingTable[201] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Forest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[202] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Meadows",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[203] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Modest",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[204] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[205] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Tropical",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[206] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Marshy",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[207] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Rocky",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[208] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Water",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[209] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Embittered",
     ['result'] = "Common",
     ['chance'] = 15
    }
  breedingTable[210] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Common",
     ['result'] = "Cultivated",
     ['chance'] = 12
    }
  breedingTable[211] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Cultivated",
     ['result'] = "Eldritch",
     ['chance'] = 12
    }
  breedingTable[212] = {
     ['allele1'] = "Cultivated",
     ['specialConditions'] = {},
     ['allele2'] = "Eldritch",
     ['result'] = "Esoteric",
     ['chance'] = 10
    }
  breedingTable[213] = {
     ['allele1'] = "Eldritch",
     ['specialConditions'] = {},
     ['allele2'] = "Esoteric",
     ['result'] = "Mysterious",
     ['chance'] = 8
    }
  breedingTable[214] = {
     ['allele1'] = "Esoteric",
     ['specialConditions'] = {},
     ['allele2'] = "Mysterious",
     ['result'] = "Arcane",
     ['chance'] = 8
    }
  breedingTable[215] = {
     ['allele1'] = "Cultivated",
     ['specialConditions'] = {},
     ['allele2'] = "Eldritch",
     ['result'] = "Charmed",
     ['chance'] = 10
    }
  breedingTable[216] = {
     ['allele1'] = "Eldritch",
     ['specialConditions'] = {},
     ['allele2'] = "Charmed",
     ['result'] = "Enchanted",
     ['chance'] = 8
    }
  breedingTable[217] = {
     ['allele1'] = "Charmed",
     ['specialConditions'] = {},
     ['allele2'] = "Enchanted",
     ['result'] = "Supernatural",
     ['chance'] = 8
    }
  breedingTable[218] = {
     ['allele1'] = "Arcane",
     ['specialConditions'] = {},
     ['allele2'] = "Supernatural",
     ['result'] = "Ethereal",
     ['chance'] = 7
    }
  breedingTable[219] = {
     ['allele1'] = "Supernatural",
     ['specialConditions'] = {[1] = "Requires a foundation of Oak Leaves"},
     ['allele2'] = "Ethereal",
     ['result'] = "Windy",
     ['chance'] = 14
    }
  breedingTable[220] = {
     ['allele1'] = "Supernatural",
     ['specialConditions'] = {[1] = "Requires a foundation of Water"},
     ['allele2'] = "Ethereal",
     ['result'] = "Watery",
     ['chance'] = 14
    }
  breedingTable[221] = {
     ['allele1'] = "Supernatural",
     ['specialConditions'] = {[1] = "Requires a foundation of Bricks"},
     ['allele2'] = "Ethereal",
     ['result'] = "Earthen",
     ['chance'] = 100
    }
  breedingTable[222] = {
     ['allele1'] = "Supernatural",
     ['specialConditions'] = {[1] = "Requires a foundation of Lava"},
     ['allele2'] = "Ethereal",
     ['result'] = "Firey",
     ['chance'] = 14
    }
  breedingTable[223] = {
     ['allele1'] = "Ethereal",
     ['specialConditions'] = {},
     ['allele2'] = "Attuned",
     ['result'] = "Aware",
     ['chance'] = 10
    }
  breedingTable[224] = {
     ['allele1'] = "Ethereal",
     ['specialConditions'] = {},
     ['allele2'] = "Aware",
     ['result'] = "Spirit",
     ['chance'] = 8
    }
  breedingTable[225] = {
     ['allele1'] = "Attuned",
     ['specialConditions'] = {},
     ['allele2'] = "Aware",
     ['result'] = "Spirit",
     ['chance'] = 8
    }
  breedingTable[226] = {
     ['allele1'] = "Aware",
     ['specialConditions'] = {},
     ['allele2'] = "Spirit",
     ['result'] = "Soul",
     ['chance'] = 7
    }
  breedingTable[227] = {
     ['allele1'] = "Monastic",
     ['specialConditions'] = {},
     ['allele2'] = "Arcane",
     ['result'] = "Pupil",
     ['chance'] = 10
    }
  breedingTable[228] = {
     ['allele1'] = "Arcane",
     ['specialConditions'] = {},
     ['allele2'] = "Pupil",
     ['result'] = "Scholarly",
     ['chance'] = 8
    }
  breedingTable[229] = {
     ['allele1'] = "Pupil",
     ['specialConditions'] = {},
     ['allele2'] = "Scholarly",
     ['result'] = "Savant",
     ['chance'] = 6
    }
  breedingTable[230] = {
     ['allele1'] = "Imperial",
     ['specialConditions'] = {},
     ['allele2'] = "Ethereal",
     ['result'] = "Timely",
     ['chance'] = 8
    }
  breedingTable[231] = {
     ['allele1'] = "Imperial",
     ['specialConditions'] = {},
     ['allele2'] = "Timely",
     ['result'] = "Lordly",
     ['chance'] = 8
    }
  breedingTable[232] = {
     ['allele1'] = "Timely",
     ['specialConditions'] = {},
     ['allele2'] = "Lordly",
     ['result'] = "Doctoral",
     ['chance'] = 7
    }
  breedingTable[233] = {
     ['allele1'] = "Infernal",
     ['specialConditions'] = {[1] = "Occurs within a Nether biome"},
     ['allele2'] = "Eldritch",
     ['result'] = "Hateful",
     ['chance'] = 9
    }
  breedingTable[234] = {
     ['allele1'] = "Infernal",
     ['specialConditions'] = {},
     ['allele2'] = "Hateful",
     ['result'] = "Spiteful",
     ['chance'] = 7
    }
  breedingTable[235] = {
     ['allele1'] = "Demonic",
     ['specialConditions'] = {},
     ['allele2'] = "Spiteful",
     ['result'] = "Withering",
     ['chance'] = 6
    }
  breedingTable[236] = {
     ['allele1'] = "Modest",
     ['specialConditions'] = {},
     ['allele2'] = "Eldritch",
     ['result'] = "Skulking",
     ['chance'] = 12
    }
  breedingTable[237] = {
     ['allele1'] = "Tropical",
     ['specialConditions'] = {},
     ['allele2'] = "Skulking",
     ['result'] = "Spidery",
     ['chance'] = 10
    }
  breedingTable[238] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Ethereal",
     ['result'] = "Ghastly",
     ['chance'] = 9
    }
  breedingTable[239] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Hateful",
     ['result'] = "Smouldering",
     ['chance'] = 7
    }
  breedingTable[240] = {
     ['allele1'] = "Ethereal",
     ['specialConditions'] = {},
     ['allele2'] = "Oblivion",
     ['result'] = "Nameless",
     ['chance'] = 10
    }
  breedingTable[241] = {
     ['allele1'] = "Oblivion",
     ['specialConditions'] = {},
     ['allele2'] = "Nameless",
     ['result'] = "Abandoned",
     ['chance'] = 8
    }
  breedingTable[242] = {
     ['allele1'] = "Nameless",
     ['specialConditions'] = {},
     ['allele2'] = "Abandoned",
     ['result'] = "Forlorn",
     ['chance'] = 6
    }
  breedingTable[243] = {
     ['allele1'] = "Imperial",
     ['specialConditions'] = {[1] = "Occurs within a End biome"},
     ['allele2'] = "Abandoned",
     ['result'] = "Draconic",
     ['chance'] = 6
    }
  breedingTable[244] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Eldritch",
     ['result'] = "Mutable",
     ['chance'] = 12
    }
  breedingTable[245] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Mutable",
     ['result'] = "Transmuting",
     ['chance'] = 9
    }
  breedingTable[246] = {
     ['allele1'] = "Unusual",
     ['specialConditions'] = {},
     ['allele2'] = "Mutable",
     ['result'] = "Crumbling",
     ['chance'] = 9
    }
  breedingTable[247] = {
     ['allele1'] = "Mystical",
     ['specialConditions'] = {},
     ['allele2'] = "Mutable",
     ['result'] = "Invisible",
     ['chance'] = 15
    }
  breedingTable[248] = {
     ['allele1'] = "Industrious",
     ['specialConditions'] = {[1] = "Requires a foundation of Copper Block"},
     ['allele2'] = "Meadows",
     ['result'] = "Cuprum",
     ['chance'] = 12
    }
  breedingTable[249] = {
     ['allele1'] = "Industrious",
     ['specialConditions'] = {[1] = "Requires a foundation of Tin Block"},
     ['allele2'] = "Forest",
     ['result'] = "Stannum",
     ['chance'] = 12
    }
  breedingTable[250] = {
     ['allele1'] = "Common",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Iron"},
     ['allele2'] = "Industrious",
     ['result'] = "Ferrous",
     ['chance'] = 12
    }
  breedingTable[251] = {
     ['allele1'] = "Stannum",
     ['specialConditions'] = {[1] = "Requires a foundation of Lead Block"},
     ['allele2'] = "Common",
     ['result'] = "Plumbum",
     ['chance'] = 10
    }
  breedingTable[252] = {
     ['allele1'] = "Imperial",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Silver"},
     ['allele2'] = "Modest",
     ['result'] = "Argentum",
     ['chance'] = 8
    }
  breedingTable[253] = {
     ['allele1'] = "Imperial",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Gold"},
     ['allele2'] = "Plumbum",
     ['result'] = "Auric",
     ['chance'] = 8
    }
  breedingTable[254] = {
     ['allele1'] = "Industrious",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Ardite"},
     ['allele2'] = "Infernal",
     ['result'] = "Ardite",
     ['chance'] = 9
    }
  breedingTable[255] = {
     ['allele1'] = "Imperial",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Cobalt"},
     ['allele2'] = "Infernal",
     ['result'] = "Cobalt",
     ['chance'] = 9
    }
  breedingTable[256] = {
     ['allele1'] = "Ardite",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Manyullyn"},
     ['allele2'] = "Cobalt",
     ['result'] = "Manyullyn",
     ['chance'] = 9
    }
  breedingTable[257] = {
     ['allele1'] = "Austere",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Diamond"},
     ['allele2'] = "Auric",
     ['result'] = "Diamandi",
     ['chance'] = 7
    }
  breedingTable[258] = {
     ['allele1'] = "Austere",
     ['specialConditions'] = {[1] = "Requires a foundation of Block of Emerald"},
     ['allele2'] = "Argentum",
     ['result'] = "Esmeraldi",
     ['chance'] = 6
    }
  breedingTable[259] = {
     ['allele1'] = "Rural",
     ['specialConditions'] = {[1] = "Requires a foundation of Apatite Ore"},
     ['allele2'] = "Cuprum",
     ['result'] = "Apatine",
     ['chance'] = 12
    }
  breedingTable[260] = {
     ['allele1'] = "Windy",
     ['specialConditions'] = {[1] = "Requires a foundation of Air Crystal Cluster"},
     ['allele2'] = "Windy",
     ['result'] = "Aer",
     ['chance'] = 8
    }
  breedingTable[261] = {
     ['allele1'] = "Firey",
     ['specialConditions'] = {[1] = "Requires a foundation of Fire Crystal Cluster"},
     ['allele2'] = "Firey",
     ['result'] = "Ignis",
     ['chance'] = 8
    }
  breedingTable[262] = {
     ['allele1'] = "Watery",
     ['specialConditions'] = {[1] = "Requires a foundation of Water Crystal Cluster"},
     ['allele2'] = "Watery",
     ['result'] = "Aqua",
     ['chance'] = 8
    }
  breedingTable[263] = {
     ['allele1'] = "Earthen",
     ['specialConditions'] = {[1] = "Requires a foundation of Earth Crystal Cluster"},
     ['allele2'] = "Earthen",
     ['result'] = "Solum",
     ['chance'] = 8
    }
  breedingTable[264] = {
     ['allele1'] = "Ethereal",
     ['specialConditions'] = {[1] = "Requires a foundation of Order Crystal Cluster"},
     ['allele2'] = "Arcane",
     ['result'] = "Ordered",
     ['chance'] = 8
    }
  breedingTable[265] = {
     ['allele1'] = "Ethereal",
     ['specialConditions'] = {[1] = "Requires a foundation of Entropy Crystal Cluster"},
     ['allele2'] = "Supernatural",
     ['result'] = "Chaotic",
     ['chance'] = 8
    }
  breedingTable[266] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Windy",
     ['result'] = "Batty",
     ['chance'] = 9
    }
  breedingTable[267] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Pupil",
     ['result'] = "Brainy",
     ['chance'] = 9
    }
  breedingTable[268] = {
     ['allele1'] = "Common",
     ['specialConditions'] = {[1] = "Occurs within a Forest biome"},
     ['allele2'] = "Skulking",
     ['result'] = "Poultry",
     ['chance'] = 12
    }
  breedingTable[269] = {
     ['allele1'] = "Common",
     ['specialConditions'] = {[1] = "Occurs within a Plains biome"},
     ['allele2'] = "Skulking",
     ['result'] = "Beefy",
     ['chance'] = 12
    }
  breedingTable[270] = {
     ['allele1'] = "Common",
     ['specialConditions'] = {[1] = "Occurs within a Mountain biome"},
     ['allele2'] = "Skulking",
     ['result'] = "Porcine",
     ['chance'] = 12
    }
  breedingTable[271] = {
     ['allele1'] = "Arcane",
     ['specialConditions'] = {},
     ['allele2'] = "Ethereal",
     ['result'] = "Essence",
     ['chance'] = 10
    }
  breedingTable[272] = {
     ['allele1'] = "Arcane",
     ['specialConditions'] = {},
     ['allele2'] = "Essence",
     ['result'] = "Quintessential",
     ['chance'] = 7
    }
  breedingTable[273] = {
     ['allele1'] = "Essence",
     ['specialConditions'] = {},
     ['allele2'] = "Windy",
     ['result'] = "Luft",
     ['chance'] = 10
    }
  breedingTable[274] = {
     ['allele1'] = "Essence",
     ['specialConditions'] = {},
     ['allele2'] = "Earthen",
     ['result'] = "Erde",
     ['chance'] = 10
    }
  breedingTable[275] = {
     ['allele1'] = "Essence",
     ['specialConditions'] = {},
     ['allele2'] = "Firey",
     ['result'] = "Feuer",
     ['chance'] = 10
    }
  breedingTable[276] = {
     ['allele1'] = "Essence",
     ['specialConditions'] = {},
     ['allele2'] = "Watery",
     ['result'] = "Wasser",
     ['chance'] = 10
    }
  breedingTable[277] = {
     ['allele1'] = "Essence",
     ['specialConditions'] = {},
     ['allele2'] = "Ethereal",
     ['result'] = "Arkanen",
     ['chance'] = 10
    }
  breedingTable[278] = {
     ['allele1'] = "Windy",
     ['specialConditions'] = {},
     ['allele2'] = "Luft",
     ['result'] = "Blitz",
     ['chance'] = 8
    }
  breedingTable[279] = {
     ['allele1'] = "Earthen",
     ['specialConditions'] = {},
     ['allele2'] = "Erde",
     ['result'] = "Staude",
     ['chance'] = 8
    }
  breedingTable[280] = {
     ['allele1'] = "Watery",
     ['specialConditions'] = {},
     ['allele2'] = "Wasser",
     ['result'] = "Eis",
     ['chance'] = 8
    }
  breedingTable[281] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Essence",
     ['result'] = "Vortex",
     ['chance'] = 8
    }
  breedingTable[282] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Ghastly",
     ['result'] = "Wight",
     ['chance'] = 8
    }
  breedingTable[283] = {
     ['allele1'] = "Stannum",
     ['specialConditions'] = {[1] = "Requires a foundation of Bronze Block"},
     ['allele2'] = "Cuprum",
     ['result'] = "Tinker",
     ['chance'] = 12
    }
  breedingTable[284] = {
     ['allele1'] = "Auric",
     ['specialConditions'] = {[1] = "Requires a foundation of Electrum Block"},
     ['allele2'] = "Argentum",
     ['result'] = "Electrum",
     ['chance'] = 10
    }
  breedingTable[285] = {
     ['allele1'] = "Ferrous",
     ['specialConditions'] = {[1] = "Requires a foundation of Ferrous Block"},
     ['allele2'] = "Esoteric",
     ['result'] = "Nickel",
     ['chance'] = 14
    }
  breedingTable[286] = {
     ['allele1'] = "Ferrous",
     ['specialConditions'] = {[1] = "Requires a foundation of Invar Block"},
     ['allele2'] = "Nickel",
     ['result'] = "Invar",
     ['chance'] = 14
    }
  breedingTable[287] = {
     ['allele1'] = "Nickel",
     ['specialConditions'] = {[1] = "Requires a foundation of Shiny Block"},
     ['allele2'] = "Invar",
     ['result'] = "Platinum",
     ['chance'] = 10
    }
  breedingTable[288] = {
     ['allele1'] = "Spiteful",
     ['specialConditions'] = {[1] = "Requires a foundation of Coal Ore"},
     ['allele2'] = "Stannum",
     ['result'] = "Carbon",
     ['chance'] = 12
    }
  breedingTable[289] = {
     ['allele1'] = "Spiteful",
     ['specialConditions'] = {[1] = "Requires a foundation of Redstone Ore"},
     ['allele2'] = "Industrious",
     ['result'] = "Destabilized",
     ['chance'] = 12
    }
  breedingTable[290] = {
     ['allele1'] = "Smouldering",
     ['specialConditions'] = {[1] = "Requires a foundation of Glowstone"},
     ['allele2'] = "Infernal",
     ['result'] = "Lux",
     ['chance'] = 12
    }
  breedingTable[291] = {
     ['allele1'] = "Smouldering",
     ['specialConditions'] = {},
     ['allele2'] = "Austere",
     ['result'] = "Dante",
     ['chance'] = 12
    }
  breedingTable[292] = {
     ['allele1'] = "Dante",
     ['specialConditions'] = {},
     ['allele2'] = "Carbon",
     ['result'] = "Pyro",
     ['chance'] = 8
    }
  breedingTable[293] = {
     ['allele1'] = "Skulking",
     ['specialConditions'] = {},
     ['allele2'] = "Wintry",
     ['result'] = "Blizzy",
     ['chance'] = 12
    }
  breedingTable[294] = {
     ['allele1'] = "Blizzy",
     ['specialConditions'] = {},
     ['allele2'] = "Icy",
     ['result'] = "Gelid",
     ['chance'] = 8
    }
  breedingTable[295] = {
     ['allele1'] = "Platinum",
     ['specialConditions'] = {},
     ['allele2'] = "Oblivion",
     ['result'] = "Winsome",
     ['chance'] = 12
    }
  breedingTable[296] = {
     ['allele1'] = "Winsome",
     ['specialConditions'] = {[1] = "Requires a foundation of Enderium Block"},
     ['allele2'] = "Carbon",
     ['result'] = "Endearing",
     ['chance'] = 8
    }
  breedingTable[297] = {
     ['allele1'] = "Windy",
     ['specialConditions'] = {[1] = "Requires a foundation of Skystone"},
     ['allele2'] = "Earthen",
     ['result'] = "Skystone",
     ['chance'] = 20
    }
  breedingTable[298] = {
     ['allele1'] = "Skystone",
     ['specialConditions'] = {},
     ['allele2'] = "Ferrous",
     ['result'] = "Silicon",
     ['chance'] = 17
    }
  breedingTable[299] = {
     ['allele1'] = "Silicon",
     ['specialConditions'] = {},
     ['allele2'] = "Energetic",
     ['result'] = "Infinity",
     ['chance'] = 20
    }
  return breedingTable
end

logger = Log()
config = Config('.openbee/config')
application = App({...})
application:parseArgs()
application:main()
logger:finish()
