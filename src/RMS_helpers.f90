module RMS_helpers
   !
   ! This module contains several useful subroutines required to compute RMS
   ! diagnostics
   !

   use precision_mod
   use parallel_mod
   use LMmapping, only: ml_mappings
   use communications, only: reduce_radial
   use truncation, only: l_max, lm_max_dtB, n_r_max, lm_max, n_mlo_loc
   use blocking, only: lm2, st_map
   use radial_functions, only: or2, rscheme_oc, r
   use horizontal_data, only: dLh
   use useful, only: cc2real
   use integration, only: rInt_R
   use LMmapping
   use constants, only: vol_oc, one

   implicit none

   private

   public :: get_PolTorRms, hInt2dPol, hInt2Pol, hInt2Tor, &
   &         hIntRms, hInt2PolLM, hInt2TorLM, hInt2dPolLM, &
   &         hInt2Pol_dist, hInt2PolLM_dist, hInt2TorLM_dist

contains

   subroutine get_PolTorRms(Pol,drPol,Tor,llm,ulm,PolRms,TorRms, &
              &             PolAsRms,TorAsRms,map)
      !
      !  calculates integral PolRms=sqrt( Integral (pol^2 dV) )
      !  calculates integral TorRms=sqrt( Integral (tor^2 dV) )
      !  plus axisymmetric parts.
      !  integration in theta,phi by summation of spherical harmonics
      !  integration in r by using Chebycheff integrals
      !  The mapping map gives the mapping lm to l,m for the input
      !  arrays Pol,drPol and Tor
      !  Output: PolRms,TorRms,PolAsRms,TorAsRms
      !

      !-- Input variables:
      integer,         intent(in) :: llm
      integer,         intent(in) :: ulm
      complex(cp),     intent(in) :: Pol(llm:ulm,n_r_max)   ! Poloidal field Potential
      complex(cp),     intent(in) :: drPol(llm:ulm,n_r_max) ! Radial derivative of Pol
      complex(cp),     intent(in) :: Tor(llm:ulm,n_r_max)   ! Toroidal field Potential
      type(mappings),  intent(in) :: map

      !-- Output variables:
      real(cp), intent(out) :: PolRms,PolAsRms
      real(cp), intent(out) :: TorRms,TorAsRms

      !-- Local variables:
      real(cp) :: PolRmsTemp,TorRmsTemp
      real(cp) :: PolRms_r(n_r_max), PolRms_r_global(n_r_max)
      real(cp) :: TorRms_r(n_r_max), TorRms_r_global(n_r_max)
      real(cp) :: PolAsRms_r(n_r_max), PolAsRms_r_global(n_r_max)
      real(cp) :: TorAsRms_r(n_r_max), TorAsRms_r_global(n_r_max)

      integer :: n_r,lm,l,m
      real(cp) :: fac

      do n_r=1,n_r_max

         PolRms_r(n_r)  =0.0_cp
         TorRms_r(n_r)  =0.0_cp
         PolAsRms_r(n_r)=0.0_cp
         TorAsRms_r(n_r)=0.0_cp

         do lm=max(2,llm),ulm
            l=map%lm2l(lm)
            m=map%lm2m(lm)
            PolRmsTemp= dLh(st_map%lm2(l,m)) * (                        &
            &    dLh(st_map%lm2(l,m))*or2(n_r)*cc2real(Pol(lm,n_r),m) + &
            &    cc2real(drPol(lm,n_r),m) )
            TorRmsTemp=   dLh(st_map%lm2(l,m))*cc2real(Tor(lm,n_r),m)
            if ( m == 0 ) then  ! axisymmetric part
               PolAsRms_r(n_r)=PolAsRms_r(n_r) + PolRmsTemp
               TorAsRms_r(n_r)=TorAsRms_r(n_r) + TorRmsTemp
            else
               PolRms_r(n_r)  =PolRms_r(n_r)   + PolRmsTemp
               TorRms_r(n_r)  =TorRms_r(n_r)   + TorRmsTemp
            end if
         end do    ! do loop over lms in block
         PolRms_r(n_r)=PolRms_r(n_r) + PolAsRms_r(n_r)
         TorRms_r(n_r)=TorRms_r(n_r) + TorAsRms_r(n_r)
      end do    ! radial grid points

      call reduce_radial(PolRms_r, PolRms_r_global, 0)
      call reduce_radial(PolAsRms_r, PolAsRms_r_global, 0)
      call reduce_radial(TorRms_r, TorRms_r_global, 0)
      call reduce_radial(TorAsRms_r, TorAsRms_r_global, 0)

      if ( coord_r == 0 ) then
         !-- Radial Integrals:
         PolRms  =rInt_R(PolRms_r_global,r,rscheme_oc)
         TorRms  =rInt_R(TorRms_r_global,r,rscheme_oc)
         PolAsRms=rInt_R(PolAsRms_r_global,r,rscheme_oc)
         TorAsRms=rInt_R(TorAsRms_r_global,r,rscheme_oc)
         fac=one/vol_oc
         PolRms  =sqrt(fac*PolRms)
         TorRms  =sqrt(fac*TorRms)
         PolAsRms=sqrt(fac*PolAsRms)
         TorAsRms=sqrt(fac*TorAsRms)
      end if

   end subroutine get_PolTorRms
!-----------------------------------------------------------------------------
   subroutine hInt2dPol(dPol,lmStart,lmStop,Pol2hInt,map)

      !-- Input variables:
      integer,         intent(in) :: lmStart,lmStop
      complex(cp),     intent(in) :: dPol(lmStart:lmStop)   ! Toroidal field Potential
      type(mappings),  intent(in) :: map

      !-- Output variables:
      real(cp), intent(inout) :: Pol2hInt(0:l_max)

      !-- Local variables:
      real(cp) :: help
      integer :: lm,l,m

      do lm=lmStart,lmStop
         l=map%lm2l(lm)
         m=map%lm2m(lm)
         help=dLh(st_map%lm2(l,m))*cc2real(dPol(lm),m)
         Pol2hInt(l)=Pol2hInt(l)+help
      end do

   end subroutine hInt2dPol
!-----------------------------------------------------------------------------
   subroutine hInt2dPolLM(dPol,lmStart,lmStop,Pol2hInt,map)

      !-- Input variables
      integer,         intent(in) :: lmStart,lmStop
      complex(cp),     intent(in) :: dPol(lmStart:lmStop)
      type(mappings),  intent(in) :: map

      !-- Output variables
      real(cp), intent(inout) :: Pol2hInt(lmStart:lmStop)

      !-- Local variables
      real(cp) :: help
      integer :: lm,l,m

      do lm=lmStart,lmStop
         l=map%lm2l(lm)
         m=map%lm2m(lm)
         help=dLh(st_map%lm2(l,m))*cc2real(dPol(lm),m)
         Pol2hInt(lm)=Pol2hInt(lm)+help
      end do

   end subroutine hInt2dPolLM
!-----------------------------------------------------------------------------
   subroutine hInt2Pol(Pol,lb,ub,nR,lmStart,lmStop,PolLMr,Pol2hInt,map)

      !-- Input variables:
      integer,         intent(in) :: lb,ub
      complex(cp),     intent(in) :: Pol(lb:ub)   ! Poloidal field Potential
      integer,         intent(in) :: nR,lmStart,lmStop
      type(mappings),  intent(in) :: map

      !-- Output variables:
      complex(cp), intent(out) :: PolLMr(lb:ub)
      real(cp),    intent(inout) :: Pol2hInt(0:l_max)

      !-- Local variables:
      real(cp) :: help,rE2
      integer :: lm,l,m

      rE2=r(nR)*r(nR)
      do lm=lmStart,lmStop
         l=map%lm2l(lm)
         m=map%lm2m(lm)
         help=rE2*cc2real(Pol(lm),m)
         Pol2hInt(l)=Pol2hInt(l)+help
         PolLMr(lm)=rE2/dLh(st_map%lm2(l,m))*Pol(lm)
      end do

   end subroutine hInt2Pol
!-----------------------------------------------------------------------------
   subroutine hInt2Pol_dist(Pol,lb,ub,nR,PolLMr,Pol2hInt)

      !-- Input variables:
      integer,         intent(in) :: lb,ub
      complex(cp),     intent(in) :: Pol(lb:ub)   ! Poloidal field Potential
      integer,         intent(in) :: nR

      !-- Output variables:
      complex(cp), intent(out) :: PolLMr(lb:ub)
      real(cp),    intent(inout) :: Pol2hInt(0:l_max)

      !-- Local variables:
      real(cp) :: help,rE2
      integer :: i,l,m,lm_glb

      rE2=r(nR)*r(nR)
      do i=lb,ub
         if (map_mlo%m0l0==i) cycle
         l=map_mlo%i2l(i)
         m=map_mlo%i2m(i)
         lm_glb = map_glbl_st%lm2(l,m)
         help=rE2*cc2real(Pol(i),m)
         Pol2hInt(l)=Pol2hInt(l)+help
         PolLMr(i)=rE2/dLh(lm_glb)*Pol(i)
      end do

      !@>TODO
      ! Do I need to call MPI_REDUCE on Pol2hInt here? I don't have all m's for 
      ! each l locally (actually, in the old format I didn't have it either, 
      ! was this working properly before the port?)
      ! 
   end subroutine hInt2Pol_dist
!-----------------------------------------------------------------------------
   subroutine hInt2PolLM(Pol,lb,ub,nR,lmStart,lmStop,PolLMr,Pol2hInt,map)

      !-- Input variables:
      integer,         intent(in) :: lb,ub
      complex(cp),     intent(in) :: Pol(lb:ub)   ! Poloidal field Potential
      integer,         intent(in) :: nR,lmStart,lmStop
      type(mappings),  intent(in) :: map

      !-- Output variables:
      complex(cp), intent(out) :: PolLMr(lb:ub)
      real(cp),    intent(inout) :: Pol2hInt(lb:ub)

      !-- Local variables:
      real(cp) :: help,rE2
      integer :: lm,l,m

      rE2=r(nR)*r(nR)
      do lm=lmStart,lmStop
         l=map%lm2l(lm)
         m=map%lm2m(lm)
         help=rE2*cc2real(Pol(lm),m)
         Pol2hInt(lm)=Pol2hInt(lm)+help
         PolLMr(lm)=rE2/dLh(st_map%lm2(l,m))*Pol(lm)
      end do

   end subroutine hInt2PolLM
!-----------------------------------------------------------------------------
   subroutine hInt2PolLM_dist(Pol,lb,ub,nR,lmStart,lmStop,PolLMr,Pol2hInt,map)
      !
      !@> TODO get only one of the two routines here!!!!
      !

      !-- Input variables:
      integer,            intent(in) :: lb,ub
      complex(cp),        intent(in) :: Pol(lb:ub)   ! Poloidal field Potential
      integer,            intent(in) :: nR,lmStart,lmStop
      type(ml_mappings),  intent(in) :: map

      !-- Output variables:
      complex(cp), intent(out) :: PolLMr(lb:ub)
      real(cp),    intent(inout) :: Pol2hInt(lb:ub)

      !-- Local variables:
      real(cp) :: help,rE2
      integer :: lm,l,m

      rE2=r(nR)*r(nR)
      do lm=lmStart,lmStop
         l=map%i2l(lm)
         m=map%i2m(lm)
         help=rE2*cc2real(Pol(lm),m)
         Pol2hInt(lm)=Pol2hInt(lm)+help
         PolLMr(lm)=rE2/dLh(st_map%lm2(l,m))*Pol(lm)
      end do

   end subroutine hInt2PolLM_dist
!-----------------------------------------------------------------------------
   subroutine hIntRms(f,nR,lmStart,lmStop,lmP,f2hInt,map,sphertor)

      !-- Input variables
      complex(cp),    intent(in) :: f(*)
      integer,        intent(in) :: nR, lmStart, lmStop, lmP
      type(mappings), intent(in) :: map
      logical,        intent(in) :: sphertor

      !-- Output variables
      real(cp),       intent(inout) :: f2hInt(0:l_max)

      !-- Local variables
      real(cp) :: help,rE2
      integer :: lm,l,m

      rE2=r(nR)*r(nR)
      do lm=lmStart,lmStop
         if ( lmP == 0 ) then
            l=map%lm2l(lm)
            m=map%lm2m(lm)
         else
            l=map%lmP2l(lm)
            m=map%lmP2m(lm)
         end if

         if ( l <= l_max ) then
            if ( sphertor ) then
               ! The l(l+1) factor comes from the orthogonality properties of
               ! vector spherical harmonics
#ifdef WITH_SHTNS
               help=rE2*cc2real(f(lm),m)*l*(l+one)!*l*(l+1)
#else
               if ( l /= 0 ) then
                  help=rE2*cc2real(f(lm),m)/(l*(l+one))
               else
                  help=rE2*cc2real(f(lm),m)
               end if
#endif
            else
               help=rE2*cc2real(f(lm),m)
            end if
            f2hInt(l)=f2hInt(l)+help
         end if
      end do

   end subroutine hIntRms
!-----------------------------------------------------------------------------
   subroutine hInt2Tor(Tor,lb,ub,nR,lmStart,lmStop,Tor2hInt,map)

      !-- Input variables:
      integer,         intent(in) :: lb,ub
      complex(cp),     intent(in) :: Tor(lb:ub)   ! Toroidal field Potential
      integer,         intent(in) :: nR
      integer,         intent(in) :: lmStart,lmStop
      type(mappings),  intent(in) :: map

      !-- Output variables:
      real(cp),        intent(inout) :: Tor2hInt(0:l_max)

      !-- Local variables:
      real(cp) :: help,rE4
      integer :: lm,l,m

      rE4=r(nR)**4
      do lm=lmStart,lmStop
         l=map%lm2l(lm)
         m=map%lm2m(lm)
         help=rE4/dLh(st_map%lm2(l,m))*cc2real(Tor(lm),m)
         Tor2hInt(l)=Tor2hInt(l)+help
      end do

   end subroutine hInt2Tor
!-----------------------------------------------------------------------------
   subroutine hInt2TorLM(Tor,lb,ub,nR,lmStart,lmStop,Tor2hInt,map)

      !-- Input variables:
      integer,         intent(in) :: lb,ub
      complex(cp),     intent(in) :: Tor(lb:ub)   ! Toroidal field Potential
      integer,         intent(in) :: nR
      integer,         intent(in) :: lmStart,lmStop
      type(mappings),  intent(in) :: map

      !-- Output variables:
      real(cp),        intent(inout) :: Tor2hInt(lb:ub)

      !-- Local variables:
      real(cp) :: help,rE4
      integer :: lm,l,m

      rE4=r(nR)**4
      do lm=lmStart,lmStop
         l=map%lm2l(lm)
         m=map%lm2m(lm)
         help=rE4/dLh(st_map%lm2(l,m))*cc2real(Tor(lm),m)
         Tor2hInt(lm)=Tor2hInt(lm)+help
      end do

   end subroutine hInt2TorLM
!-----------------------------------------------------------------------------
   subroutine hInt2TorLM_dist(Tor,lb,ub,nR,lmStart,lmStop,Tor2hInt,map)
      !
      !@> TODO get only one of the two routines here!!!!
      !

      !-- Input variables:
      integer,           intent(in) :: lb,ub
      complex(cp),       intent(in) :: Tor(lb:ub)   ! Toroidal field Potential
      integer,           intent(in) :: nR
      integer,           intent(in) :: lmStart,lmStop
      type(ml_mappings), intent(in) :: map

      !-- Output variables:
      real(cp),        intent(inout) :: Tor2hInt(lb:ub)

      !-- Local variables:
      real(cp) :: help,rE4
      integer :: lm,l,m

      rE4=r(nR)**4
      do lm=lmStart,lmStop
         l=map%i2l(lm)
         m=map%i2m(lm)
         help=rE4/dLh(st_map%lm2(l,m))*cc2real(Tor(lm),m)
         Tor2hInt(lm)=Tor2hInt(lm)+help
      end do

   end subroutine hInt2TorLM_dist
!-----------------------------------------------------------------------------
end module RMS_helpers
