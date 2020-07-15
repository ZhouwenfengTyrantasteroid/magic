module fft
   !
   ! This is the FFTW version of the fft module
   !

   use iso_c_binding
   use omp_lib
   use precision_mod
   use constants, only: zero
   use truncation, only: n_phi_max, n_theta_loc

   implicit none

   include 'fftw3.f03'

   type(c_ptr) :: plan_fwd, plan_bwd
   integer(c_int), parameter :: fftw_plan_flag=FFTW_PATIENT

   public :: init_fft, finalize_fft, fft_many, ifft_many, fft_to_real

contains 

   subroutine init_fft(n_points)
      !
      ! Set-up FFTW plans for Complex -> Real and Real -> Complex transforms
      !

      !-- Input variable
      integer, intent(in) :: n_points

      !-- Local variables
      complex(cp) :: dat_in(n_theta_loc, n_points/2+1)
      real(cp) :: dat_out(n_theta_loc, n_points)
      integer :: inembed(1), onembed(1), istride, ostride, odist, idist, n(1)
      integer :: howmany
#ifdef WITHOMP
      integer :: n_threads, ier

      ier =  fftw_init_threads()
      n_threads = omp_get_num_threads()
      call fftw_plan_with_nthreads(n_threads)
#endif
      n = [n_points]
      howmany = n_theta_loc
      inembed = n_points/2+1
      onembed = n_points
      istride = n_theta_loc
      ostride = n_theta_loc
      idist = 1
      odist = 1
      plan_bwd = fftw_plan_many_dft_c2r(1, n, howmany, dat_in,              &
                 &                      inembed, istride, idist, dat_out,   &
                 &                      onembed, ostride, odist, fftw_plan_flag)

      plan_fwd = fftw_plan_many_dft_r2c(1, n, howmany, dat_out,               &
                 &                      onembed, istride, idist, dat_in,      &
                 &                      inembed, ostride, odist, fftw_plan_flag)

   end subroutine init_fft
!-----------------------------------------------------------------------------------
   subroutine finalize_fft
      !
      ! Destroy FFTW plans
      !

      call fftw_destroy_plan(plan_fwd)
      call fftw_destroy_plan(plan_bwd)

   end subroutine finalize_fft
!-----------------------------------------------------------------------------------
   subroutine fft_to_real(f,ld_f,nrep)
      !@ TODO> Right now this works only for SHTns config like (i.e. out of
      !place with n_phi_max points and not n_phi_max+2)

      !-- Input variables
      integer,  intent(in) :: ld_f,nrep

      !-- Inout variable
      real(cp), intent(inout) :: f(ld_f,nrep)

      !-- Local variables
      type(c_ptr) :: plan_bwd
      complex(cp) :: fcplx(ld_f/2+1,nrep)
      integer :: inembed(1), onembed(1), istride, ostride, odist, idist, n(1), np, nr

      inembed(1) = 0
      onembed(1) = 0
      istride = 1
      ostride = 1
      odist = ld_f ! or 2*(ld_f/2+1) if in-place
      idist = ld_f/2+1
      n(1)=ld_f

      plan_bwd = fftw_plan_many_dft_c2r(1, n, nrep, fcplx, inembed, istride, idist, &
                 &                      f, onembed, ostride, odist, FFTW_ESTIMATE)

      do nr=1,nrep
         do np=1,ld_f/2
            fcplx(np,nr)=cmplx(f(2*np-1,nr),f(2*np,nr),cp)
         end do
         fcplx(ld_f/2+1,nr)=zero
      end do

      call fftw_execute_dft_c2r(plan_bwd, fcplx, f)
      call fftw_destroy_plan(plan_bwd)

   end subroutine fft_to_real
!-----------------------------------------------------------------------------------
   subroutine fft_many(f, g)
      !
      ! Real -> complex FFT: f(nlat,nlon) -> fhat(nlat,nlon/2+1)
      !

      !-- Input variable:
      real(cp),    intent(inout)  :: f(:,:)

      !-- Output variable:
      complex(cp), intent(out) :: g(n_theta_loc,(n_phi_max/2+1))
      
      call fftw_execute_dft_r2c(plan_fwd, f, g)
      g(:,:)=g(:,:)/n_phi_max

   end subroutine fft_many
!-----------------------------------------------------------------------------------
   subroutine ifft_many(g, f)
      !
      ! Complex -> real iFFT: fhat(nlat,nlon/2+1) -> f(nlat,nlon)
      !

      !-- Input variable:
      complex(cp), intent(inout)  :: g(:,:)

      !-- Output variable:
      real(cp),    intent(out) :: f(n_theta_loc,n_phi_max)
      
      call fftw_execute_dft_c2r(plan_bwd, g, f)

   end subroutine ifft_many
!-----------------------------------------------------------------------------------
end module fft
