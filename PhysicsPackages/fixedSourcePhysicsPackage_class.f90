module fixedSourcePhysicsPackage_class

  use numPrecision
  use universalVariables
  use endfConstants
  use genericProcedures,              only : fatalError, printFishLineR, numToChar, rotateVector
  use hashFunctions_func,             only : FNV_1
  use dictionary_class,               only : dictionary
  use outputFile_class,               only : outputFile

  ! Timers
  use timer_mod,                      only : registerTimer, timerStart, timerStop, &
                                             timerTime, timerReset, secToChar

  ! Particle classes and Random number generator
  use particle_class,                 only : particle, P_NEUTRON
  use particleDungeon_class,          only : particleDungeon
  use source_inter,                   only : source
  use RNG_class,                      only : RNG

  ! Physics package interface
  use physicsPackage_inter,           only : physicsPackage

  ! Geometry
  use cellGeometry_inter,             only : cellGeometry

  ! Nuclear Data
  use materialMenu_mod,               only : mm_nMat           => nMat
  use nuclearDataReg_mod,             only : ndReg_init        => init ,&
                                             ndReg_activate    => activate ,&
                                             ndReg_display     => display, &
                                             ndReg_kill        => kill, &
                                             ndReg_get         => get ,&
                                             ndReg_getMatNames => getMatNames
  use nuclearDatabase_inter,          only : nuclearDatabase
  use neutronMaterial_inter,          only : neutronMaterial, neutronMaterial_CptrCast
  use ceNeutronMaterial_class,        only : ceNeutronMaterial
  use mgNeutronMaterial_inter,        only : mgNeutronMaterial
  use fissionCE_class,                only : fissionCE, fissionCE_TptrCast
  use fissionMG_class,                only : fissionMG, fissionMG_TptrCast
  use ceNeutronDatabase_inter,        only : ceNeutronDatabase, ceNeutronDatabase_CptrCast

  ! Operators
  use collisionOperator_class,        only : collisionOperator
  use transportOperator_inter,        only : transportOperator

  ! Tallies
  use tallyCodes
  use tallyAdmin_class,               only : tallyAdmin

  ! Factories
  use geometryFactory_func,           only : new_cellGeometry_ptr
  use transportOperatorFactory_func,  only : new_transportOperator
  use sourceFactory_func,             only : new_source

  implicit none
  private

  !!
  !! Physics Package for fixed source calculations
  !!
  type, public,extends(physicsPackage) :: fixedSourcePhysicsPackage
    private
    ! Building blocks
    class(nuclearDatabase), pointer        :: nucData => null()
    class(cellGeometry), pointer           :: geom    => null()
    type(collisionOperator)                :: collOp
    class(transportOperator), allocatable  :: transOp
    class(RNG), pointer                    :: pRNG    => null()
    type(tallyAdmin),pointer               :: tally   => null()

    ! Settings
    integer(shortInt)  :: N_batches
    integer(shortInt)  :: pop
    character(pathLen) :: outputFile
    integer(shortInt)  :: printSource = 0
    integer(shortInt)  :: particleType

    ! Calculation components
    type(particleDungeon), pointer :: thisBatch    => null()
    class(source), allocatable     :: fixedSource

    ! Timer bins
    integer(shortInt) :: timerMain

  contains
    procedure :: init
    procedure :: printSettings
    procedure :: batches
    procedure :: collectResults
    procedure :: run
    procedure :: kill

  end type fixedSourcePhysicsPackage

contains

  subroutine run(self)
    class(fixedSourcePhysicsPackage), intent(inout) :: self

    print *, repeat("<>",50)
    print *, "/\/\ FIXED SOURCE CALCULATION /\/\" 

    call self % batches(self % tally, self % N_batches)
    call self % collectResults()

    print *
    print *, "\/\/ END OF FIXED SOURCE CALCULATION \/\/"
    print *
  end subroutine

  !!
  !!
  !!
  subroutine batches(self, tally, N_batches)
    class(fixedSourcePhysicsPackage), intent(inout) :: self
    type(tallyAdmin), pointer,intent(inout)         :: tally
    integer(shortInt), intent(in)                   :: N_batches
    integer(shortInt)                               :: i, N
    type(particle)                                  :: p
    real(defReal)                                   :: elapsed_T, end_T, T_toEnd
    character(100),parameter :: Here ='batches (fixedSourcePhysicsPackage_class.f90)'

    N = self % pop

    ! Attach nuclear data and RNG to particle
    p % pRNG   => self % pRNG

    ! Reset and start timer
    call timerReset(self % timerMain)
    call timerStart(self % timerMain)

    do i=1,N_batches

      ! Send start of cycle report
      call self % fixedSource % generate(self % thisBatch, N)
      if(self % printSource == 1) then
        call self % thisBatch % printToFile(trim(self % outputFile)//'_source'//numToChar(i))
      end if

      call tally % reportCycleStart(self % thisBatch)

      gen: do
        ! Obtain paticle from dungeon
        call self % thisBatch % release(p)
        call self % geom % placeCoord(p % coords)

        ! Save state
        call p % savePreHistory()

          ! Transport particle untill its death
          history: do
            call self % transOp % transport(p, tally, self % thisBatch, self % thisBatch)
            if(p % isDead) exit history

            call self % collOp % collide(p, tally ,self % thisBatch, self % thisBatch)
            if(p % isDead) exit history
          end do history

        if( self % thisBatch % isEmpty()) exit gen
      end do gen

      ! Send end of cycle report
      call tally % reportCycleEnd(self % thisBatch)

      ! Calculate times
      call timerStop(self % timerMain)
      elapsed_T = timerTime(self % timerMain)

      ! Predict time to end
      end_T = real(N_batches,defReal) * elapsed_T / i
      T_toEnd = max(ZERO, end_T - elapsed_T)


      ! Display progress
      call printFishLineR(i)
      print *
      print *, 'Batch: ', numToChar(i), ' of ', numToChar(N_batches)
      print *, 'Elapsed time: ', trim(secToChar(elapsed_T))
      print *, 'End time:     ', trim(secToChar(end_T))
      print *, 'Time to end:  ', trim(secToChar(T_toEnd))
      call tally % display()
    end do
  end subroutine batches

  !!
  !! Print calculation results to file
  !!
  subroutine collectResults(self)
    class(fixedSourcePhysicsPackage), intent(in) :: self
    type(outputFile)                             :: out
    character(pathLen)                           :: path
    character(nameLen)                           :: name

    name = 'asciiMATLAB'
    call out % init(name)

    name = 'seed'
    call out % printValue(self % pRNG % getSeed(),name)

    name = 'pop'
    call out % printValue(self % pop,name)

    name = 'Batches'
    call out % printValue(self % N_batches,name)

    ! Print tally
    call self % tally % print(out)

    path = trim(self % outputFile) // '.m'
    call out % writeToFile(path)

  end subroutine collectResults


  !!
  !! Initialise from individual components and dictionaries for inactive and active tally
  !!
  subroutine init(self, dict)
    class(fixedSourcePhysicsPackage), intent(inout) :: self
    class(dictionary), intent(inout)                :: dict
    class(dictionary),pointer                       :: tempDict
    integer(shortInt)                               :: seed_temp
    integer(longInt)                                :: seed
    character(10)                                   :: time
    character(8)                                    :: date
    character(:),allocatable                        :: string
    character(nameLen)                              :: nucData, energy
    integer(shortInt)                               :: i
    character(100), parameter :: Here ='init (fixedSourcePhysicsPackage_class.f90)'

    ! Read calculation settings
    call dict % get( self % pop,'pop')
    call dict % get( self % N_batches,'batch')
    call dict % get( nucData, 'XSdata')
    call dict % get( energy, 'dataType')

    ! Process type of data
    select case(energy)
      case('mg')
        self % particleType = P_NEUTRON_MG
      case('ce')
        self % particleType = P_NEUTRON_CE
      case default
        call fatalError(Here,"dataType must be 'mg' or 'ce'.")
    end select

    ! Read outputfile path
    call dict % getOrDefault(self % outputFile,'outputFile','./output')

    ! Register timer
    self % timerMain = registerTimer('transportTime')

    ! Initialise RNG
    allocate(self % pRNG)

    ! *** It is a bit silly but dictionary cannot store longInt for now
    !     so seeds are limited to 32 bits (can be -ve)
    if( dict % isPresent('seed')) then
      call dict % get(seed_temp,'seed')

    else
      ! Obtain time string and hash it to obtain random seed
      call date_and_time(date, time)
      string = date // time
      call FNV_1(string,seed_temp)

    end if
    seed = seed_temp
    call self % pRNG % init(seed)

    ! Read whether to print particle source per cycle
    call dict % getOrDefault(self % printSource, 'printSource', 0)

    ! Build Nuclear Data
    call ndReg_init(dict % getDictPtr("nuclearData"))

    ! Build geometry
    tempDict => dict % getDictPtr('geometry')
    self % geom => new_cellGeometry_ptr(tempDict, ndReg_getMatNames())

    ! Activate Nuclear Data *** All materials are active
    call ndReg_activate(self % particleType, nucData, [(i, i=1, mm_nMat())])
    self % nucData => ndReg_get(self % particleType)

    ! Read particle source definition
    tempDict => dict % getDictPtr('source')
    call new_source(self % fixedSource, tempDict, self % geom, self % pRNG)

    ! Build collision operator
    tempDict => dict % getDictPtr('collisionOperator')
    call self % collOp % init(tempDict)

    ! Build transport operator
    tempDict => dict % getDictPtr('transportOperator')
    call new_transportOperator(self % transOp, tempDict, self % geom)

    ! Initialise tally Admin
    tempDict => dict % getDictPtr('tally')
    allocate(self % tally)
    call self % tally % init(tempDict)

    call self % printSettings()

  end subroutine init

  !!
  !! Deallocate memory
  !!
  subroutine kill(self)
    class(fixedSourcePhysicsPackage), intent(inout) :: self

    ! TODO: This subroutine

  end subroutine kill

  !!
  !! Print settings of the physics package
  !!
  subroutine printSettings(self)
    class(fixedSourcePhysicsPackage), intent(in) :: self

    print *, repeat("<>",50)
    print *, "/\/\ FIXED SOURCE CALCULATION /\/\" 
    print *, "Batches:          ", numToChar(self % N_batches)
    print *, "Population:       ", numToChar(self % pop)
    print *, "Initial RNG Seed: ", numToChar(self % pRNG % getSeed())
    print *
    print *, repeat("<>",50)
  end subroutine printSettings

end module fixedSourcePhysicsPackage_class
