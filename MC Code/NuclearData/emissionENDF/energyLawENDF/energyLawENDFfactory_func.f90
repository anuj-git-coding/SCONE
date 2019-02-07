module energyLawENDFfactory_func

  use numPrecision
  use endfConstants
  use genericProcedures,  only : fatalError
  use aceCard_class,      only : aceCard

  ! Energy Laws
  use energyLawENDF_inter,     only : energyLawENDF
  use contTabularEnergy_class, only : contTabularEnergy
  use maxwellSpectrum_class,   only : maxwellSpectrum
  use levelScattering_class,   only : levelScattering
  use noEnergy_class,          only : noEnergy

  implicit none
  private

  ! Define public interface
  public :: new_energyLawENDF

contains

  !!
  !! Allocates a new energyLawENDF from aceCard and MT number
  !! aceCard can be in any poistion. Its position changes at output.
  !!
  subroutine new_energyLawENDF(new, ACE, MT)
    class(energyLawENDF),allocatable, intent(inout) :: new
    type(aceCard), intent(inout)                    :: ACE
    integer(shortInt), intent(in)                   :: MT
    integer(shortInt)                               :: LNW, LAW, loc
    character(100),parameter :: Here='new_energyLawENDF (energyLawENDFfactory_func.f90)'

    ! Protect against reactions with no energy data (absorbtions and eleastic scattering)
    if(MT == N_N_elastic) then
      allocate(new, source = noEnergy())
      return

    else if(ACE % isCaptureMT(MT)) then
      allocate(new, source = noEnergy())
      return

    end if

    ! Set aceCard read head to beginning of energy data for MT
    call ACE % setToEnergyMT(MT)

    ! Read location of next energy law. If LNW == 0 only one law is given
    LNW = ACE % readInt()

    ! Give error if multiple laws are present
    if (LNW /= 0) then
      call fatalError(Here,'Multiple energy laws for a single MT are not yet supported')

    end if

    ! Read energy Law type and location
    LAW = ACE % readInt()
    loc = ACE % readInt()

    ! Set ACE to location of the LAW
    call ACE % setToEnergyLaw(loc)

    ! Allocate new object
    select case(LAW)
      case (continuousTabularDistribution)
        allocate(new, source = contTabularEnergy(ACE))

      case (simpleMaxwellFissionSpectrum)
        allocate(new, source = maxwellSpectrum(ACE))

      case (levelScatteringLaw)
        allocate(new, source = levelScattering(ACE))

      case default
        print *, 'Energy Law Type :', LAW
        call fatalError(Here,'Energy Law Type is not recognised, yet supported or is correlated')

    end select

  end subroutine new_energyLawENDF

end module energyLawENDFfactory_func
