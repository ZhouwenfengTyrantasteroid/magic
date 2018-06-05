module truncation
   !
   !   This module defines how the points from Grid Space, LM-Space and ML-Space 
   !   are divided amonst the MPI domains.
   !   
   !   This does *not* include mappings, only lower/upper bounds and dimensions.
   ! 
   !   PS: is "truncation" still a fitting name for this module?
   !

   use precision_mod, only: cp
   use logic
   use useful, only: abortRun
   use parallel_mod
   use mpi
   
   implicit none

   !-- Global Dimensions:
   !
   !   minc here is sort of the inverse of mres in SHTns. In MagIC, the 
   !   number of m modes stored is m_max/minc+1. In SHTns, it is simply m_max.
   !   Conversely, there are m_max m modes in MagIC, though not all of them
   !   are effectivelly stored/computed. In SHTns, the number of m modes
   !   is m_max*minc+1 (therein called mres). This makes things very confusing
   !   specially because lm2 and lmP2 arrays (and their relatives) store
   !   m_max m points, and sets those which are not multiple of minc to 0.
   !   
   !   In other words, this:
   !   call shtns_lmidx(lm_idx, l_idx, m_idx/minc)
   !   returns the same as 
   !   lm_idx = lm2(l_idx, m_idx)
   !-----------------------------------------
   
   !-- Basic quantities:
   integer :: n_r_max       ! number of radial grid points
   integer :: n_cheb_max    ! max degree-1 of cheb polynomia
   integer :: n_phi_tot     ! number of longitude grid points
   integer :: n_r_ic_max    ! number of grid points in inner core
   integer :: n_cheb_ic_max ! number of chebs in inner core
   integer :: minc          ! basic wavenumber, longitude symmetry  
   integer :: nalias        ! controls dealiasing in latitude
   logical :: l_axi         ! logical for axisymmetric calculations
   character(len=72) :: radial_scheme ! radial scheme (either Cheybev of FD)
   real(cp) :: fd_stretch    ! regular intervals over irregular intervals
   real(cp) :: fd_ratio      ! drMin over drMax (only when FD are used)
   integer :: fd_order       ! Finite difference order (for now only 2 and 4 are safe)
   integer :: fd_order_bound ! Finite difference order on the  boundaries
   integer :: n_r_cmb        ! Used to belong to radial_data
   integer :: n_r_icb        ! Used to belong to radial_data
   integer :: n_r_on_last_rank ! Used to belong to radial_data
 
   !-- Derived quantities:
   integer :: n_phi_max   ! absolute number of phi grid-points
   integer :: n_theta_max ! number of theta grid-points
   integer :: n_theta_axi ! number of theta grid-points (axisymmetric models)
   integer :: l_max       ! max degree of Plms
   integer :: m_max       ! max order of Plms
   integer :: n_m_max     ! max number of ms (different oders) = m_max/minc+1
   integer :: lm_max      ! number of l/m combinations
   integer :: lmP_max     ! number of l/m combination if l runs to l_max+1
   integer :: lm_max_real ! number of l/m combination for real representation (cos/sin)
   integer :: nrp,ncp     ! dimension of phi points in for real/complex arrays
   integer :: n_r_tot     ! total number of radial grid points
 
   !-- Now quantities for magnetic fields:
   !   Set lMag=0 if you want to save this memory (see c_fields)!
   integer :: lMagMem       ! Memory for magnetic field calculation
   integer :: n_r_maxMag    ! Number of radial points to calculate magnetic field
   integer :: n_r_ic_maxMag ! Number of radial points to calculate IC magnetic field
   integer :: n_r_totMag    ! n_r_maxMag + n_r_ic_maxMag
   integer :: l_maxMag      ! Max. degree for magnetic field calculation
   integer :: lm_maxMag     ! Max. number of l/m combinations for magnetic field calculation
 
   !-- Movie memory control:
   integer :: lMovieMem      ! Memory for movies
   integer :: ldtBMem        ! Memory for movie output
   integer :: lm_max_dtB     ! Number of l/m combinations for movie output
   integer :: n_r_max_dtB    ! Number of radial points for movie output
   integer :: n_r_ic_max_dtB ! Number of IC radial points for movie output
   integer :: lmP_max_dtB    ! Number of l/m combinations for movie output if l runs to l_max+1
 
   !-- Memory control for stress output:
   integer :: lStressMem     ! Memory for stress output
   integer :: n_r_maxStr     ! Number of radial points for stress output
   integer :: n_theta_maxStr ! Number of theta points for stress output
   integer :: n_phi_maxStr   ! Number of phi points for stress output
   
   !-- General Notation:
   ! 
   ! For continuous variables:
   ! dist_V(i,1) = lower bound of direction V in rank i
   ! dist_V(i,2) = upper bound of direction V in rank i
   ! dist_V(i,0) = shortcut to dist_V(i,2) - dist_V(i,1) + 1
   !
   ! Because continuous variables are simple, we can define some shortcuts:
   ! l_V: dist_V(this_rank,1)
   ! u_V: dist_V(this_rank,2)
   ! n_V: u_V - l_V + 1  (number of local points in V direction)
   ! n_V_max: global dimensions of variable V. Basically,  MPI_ALLREDUCE(n_V,n_V_max,MPI_SUM)
   ! 
   ! For discontinuous variables:
   ! dist_V(i,0)  = how many V points are there for rank i
   ! dist_V(i,1:) = an array containing all of the V points in rank i
   ! 
   
   !-- Distributed Dimensions
   !-----------------------------------------

   !-- Distributed Grid Space 
   integer, allocatable, protected :: dist_theta(:,:)
   integer, allocatable, protected :: dist_r(:,:)
   integer, protected :: n_theta, l_theta, u_theta
   integer, protected :: n_r,     l_r,     u_r
   
   ! Helpers
   integer, protected :: l_r_Mag
   integer, protected :: l_r_Che
   integer, protected :: l_r_TP 
   integer, protected :: l_r_DC 
   integer, protected :: u_r_Mag 
   integer, protected :: u_r_Che 
   integer, protected :: u_r_TP  
   integer, protected :: u_r_DC  
   
   !-- Distributed LM-Space
   ! n_m:   total number of m's in this rank. Shortcut to dist_m(i,0)
   ! n_lm:  total number of l and m points in this rank
   ! n_lmP: total number of l and m points (for LM space with l_max+1) in this rank
   integer, allocatable, protected :: dist_m(:,:)
   integer, protected :: n_m, n_lm, n_lmP
   integer, protected :: n_m_array
   
   !-- Distributed ML-Space
   
   
   
   !--- Distributed domain - for n_ranks_theta > 1
   ! n_theta_dist(i,1): first theta point in the i-th rank
   ! n_theta_dist(i,2): last theta ppoint in the i-th rank
   ! n_theta_beg: shortcut to n_theta_dist(coord_theta,1)
   ! n_theta_end: shortcut to n_theta_dist(coord_theta,2)
   ! n_theta_loc: number of theta points in the local rank
   !-------------------------------------------------------------
   ! lm_dist - (n_ranks_theta, n_m_ext, 4)
   ! lm_dist(i,j,1): value of the j-th "m" in the i-th rank
   ! lm_dist(i,j,2): length of the j-th row in Flm_loc
   ! lm_dist(i,j,3): where the j-th row begins in Flm_loc
   ! lm_dist(i,j,4): where the j-th row ends in Flm_loc
   !-------------------------------------------------------------
   ! lmP_dist(i,j,k) : same as above, but for l_max+1 instead of l_max
   !-------------------------------------------------------------
   ! n_m_ext: number of m points in the local rank, +1. The extra
   !          point comes in when m_max + 1 is not divisible by the 
   !          number of ranks. If the extra point is "not in use"
   !          in the j-th rank, then lmP_dist(j,n_m_ext,:) = -1,
   !          and lmP_dist(j,n_m_ext,2) = 0
   !          This is useful mostly for looping over lmP_dist
   ! n_m_loc: number of points in the local rank. This coincides with
   !          n_m_ext in the ranks with extra points.
   ! 
   ! lmP_loc: shortcut to sum(lmP_dist(coord_theta,:,2))
   ! 
   ! - Lago
   integer :: n_theta_beg, n_theta_end, n_theta_loc
   integer :: n_m_ext, n_m_loc, lmP_loc, lm_loc
   integer :: lm_locMag
   integer :: lm_locChe
   integer :: lm_locTP
   integer :: lm_locDC
   integer, allocatable :: n_theta_dist(:,:), lmP_dist(:,:,:), lm_dist(:,:,:)
   
   
   
   
   
   
   
   !-- Distribution of the points amonst the ranks
   !   Contiguous directions are stored in a 2D array
   !   Discontiguous directions are stored in a 3D array
   integer, allocatable :: ml_m_dist(:,:)
   integer, allocatable :: ml_l_dist(:,:,:)
   
   
   
contains
   
   subroutine initialize_truncation
      
      integer :: n_r_maxML,n_r_ic_maxML,n_r_totML,l_maxML,lm_maxML
      integer :: lm_max_dL,lmP_max_dL,n_r_max_dL,n_r_ic_max_dL
      integer :: n_r_maxSL,n_theta_maxSL,n_phi_maxSL
      
      if ( .not. l_axi ) then
         ! absolute number of phi grid-points
         n_phi_max = n_phi_tot/minc

         ! number of theta grid-points
         n_theta_max = n_phi_tot/2

         ! max degree and order of Plms
         l_max = (nalias*n_theta_max)/30 
         m_max = (l_max/minc)*minc
      else
         n_theta_max = n_theta_axi
         n_phi_max   = 1
         n_phi_tot   = 1
         minc        = 1
         l_max       = (nalias*n_theta_max)/30 
         m_max       = 0
      end if
      
      ! max number of ms (different oders)
      n_m_max=m_max/minc+1
      
      ! number of l/m combinations
      lm_max=m_max*(l_max+1)/minc - m_max*(m_max-minc)/(2*minc)+(l_max+1-m_max)
      ! number of l/m combination if l runs to l_max+1
      lmP_max=lm_max+n_m_max
      
      ! number of l/m combination 
      ! for real representation (cos/sin)
      lm_max_real=2*lm_max
      
#if WITH_SHTNS
      nrp=n_phi_max
#else
      nrp=n_phi_max+2
#endif
      ncp=nrp/2

      ! total number of radial grid points
      n_r_tot=n_r_max+n_r_ic_max
      
      !-- Now quantities for magnetic fields:
      !    Set lMag=0 if you want to save this memory (see c_fields)!
      n_r_maxML     = lMagMem*n_r_max
      n_r_ic_maxML  = lMagMem*n_r_ic_max
      n_r_totML     = lMagMem*n_r_tot
      l_maxML       = lMagMem*l_max
      lm_maxML      = lMagMem*lm_max
      n_r_maxMag    = max(1,n_r_maxML)
      n_r_ic_maxMag = max(1,n_r_ic_maxML)
      n_r_totMag    = max(1,n_r_totML)
      l_maxMag      = max(1,l_maxML)
      lm_maxMag     = max(1,lm_maxML)
      
      !-- Movie memory control:
      lm_max_dL    =ldtBMem*lm_max
      lmP_max_dL   =ldtBMem*lmP_max
      n_r_max_dL   =ldtBMem*n_r_max
      n_r_ic_max_dL=ldtBMem*n_r_ic_max
      lm_max_dtB    =max(lm_max_DL,1) 
      lmP_max_dtB   =max(lmP_max_DL,1)
      n_r_max_dtB   =max(n_r_max_DL,1)
      n_r_ic_max_dtB=max(n_r_ic_max_DL,1)
      
      !-- Memory control for stress output:
      n_r_maxSL     = lStressMem*n_r_max
      n_theta_maxSL = lStressMem*n_theta_max
      n_phi_maxSL   = lStressMem*n_phi_max
      n_r_maxStr    = max(n_r_maxSL,1)
      n_theta_maxStr= max(n_theta_maxSL,1)
      n_phi_maxStr  = max(n_phi_maxSL,1)
      
      !-- I don't know the purpose of these two variables, but they used to 
      !   belong to radial_data. I'll keep them around. - Lago
      
      ! must be of form 4*integer+1
      ! Possible values for n_r_max:
      !  5,9,13,17,21,25,33,37,41,49,
      !  61,65,73,81,97,101,121,129, ...
      n_r_cmb = 1
      n_r_icb = n_r_max
      
   end subroutine initialize_truncation
   
   !------------------------------------------------------------------------------
   subroutine distribute_gs
      !   
      !   Takes care of the distribution of the radial points and the θ
      !   
      !   Author: Rafael Lago, MPCDF, June 2018
      !   
      
      !-- Distribute Grid Space θ
      !
      allocate(dist_theta(0:n_ranks_theta-1,0:2))
      call distribute_contiguous_last(dist_theta,n_theta_max,n_ranks_theta)
      dist_theta(:,0) = dist_theta(:,2) - dist_theta(:,1) + 1
      l_theta = dist_theta(coord_theta,1)
      u_theta = dist_theta(coord_theta,2)
      n_theta = u_theta - l_theta + 1
      
      !-- Distribute Grid Space r
      !   I'm not sure what happens if n_r_cmb/=1 and n_r_icb/=n_r_max
      allocate(dist_r(0:n_ranks_r-1,0:2))
      call distribute_contiguous_last(dist_r,n_r_max,n_ranks_r)
      
      !-- Take n_r_cmb into account
      !-- TODO check if this is correct
      dist_r(:,1:2) = dist_r(:,1:2) + n_r_cmb - 1
      
      dist_r(:,0) = dist_r(:,2) - dist_r(:,1) + 1
      n_r = dist_r(coord_r,0)
      l_r = dist_r(coord_r,1)
      u_r = dist_r(coord_r,2)
      
      !-- Setup Helpers
      !   
      l_r_Mag = l_r
      l_r_Che = l_r
      l_r_TP  = l_r
      l_r_DC  = l_r
      u_r_Mag = u_r
      u_r_Che = u_r
      u_r_TP  = u_r
      u_r_DC  = u_r
      
      if ( .not. l_mag           ) l_r_Mag = 1
      if ( .not. l_chemical_conv ) l_r_Che = 1
      if ( .not. l_TP_form       ) l_r_TP  = 1
      if ( .not. l_double_curl   ) l_r_DC  = 1
      if ( .not. l_mag           ) u_r_Mag = 1
      if ( .not. l_chemical_conv ) u_r_Che = 1
      if ( .not. l_TP_form       ) u_r_TP  = 1
      if ( .not. l_double_curl   ) u_r_DC  = 1
      
      call print_contiguous_distribution(dist_theta, n_ranks_theta, 'θ')
      call print_contiguous_distribution(dist_r, n_ranks_r, 'r')
      
   end subroutine distribute_gs
   
   !------------------------------------------------------------------------------
   subroutine distribute_lm
      !   
      !   Takes care of the distribution of the m's from the LM-space
      !   
      !   Author: Rafael Lago, MPCDF, June 2018
      !   
      
      !   R was already distributed in distribute_gs
      !   Only m is left
      
      n_m_array = ceiling(real(n_m_max) / real(n_ranks_m))
      
      allocate(dist_m( 0:n_ranks_theta-1, 0:n_m_array))
      
      call distribute_discontiguous_snake(dist_m, n_m_array, n_m_max, n_ranks_m)
      
      !-- The function above distributes contiguous points. Nothing else.
      !   Now we take care of minc:
      dist_m(:,1:) = (dist_m(:,1:)-1)*minc
      
      !-- Counts how many points were assigned to each rank
      dist_m(:,0) = count(dist_m(:,1:) >= 0, 2)
      
      n_m = dist_m(coord_m,0)
      call print_discontiguous_distribution(dist_m, n_m_array, n_ranks_theta, 'm')
      
   end subroutine distribute_lm   

!------------------------------------------------------------------------------- 
   subroutine distribute_truncation
      !   Divides the number of points in theta direction evenly amongst the 
      !   ranks; if the number of point is not round, the last first receive 
      !   one extra point. 
      !
      !-- TODO load imbalance; load imbalance everywhere. I won't mind that 
      !   now, because the ordering will be much more complicated anyway, I'll 
      !   worry about that later
      !
      !-- TODO deallocate the arrays allocated here
      !
      !   Author: Rafael Lago, MPCDF, July 2017
      !
      integer :: i, j, itmp, loc, proc_idx
      
      ! Deals with n_theta_dist
      !-------------------------------------------
      loc = n_theta_max/n_ranks_theta
      itmp = n_theta_max - loc*n_ranks_theta
      allocate(n_theta_dist(0:n_ranks_theta-1,2))
      do i=0,n_ranks_theta-1
         n_theta_dist(i,1) = loc*i + min(i,itmp) + 1
         n_theta_dist(i,2) = loc*(i+1) + min(i+1,itmp)
      end do
      n_theta_beg = n_theta_dist(coord_theta,1)
      n_theta_end = n_theta_dist(coord_theta,2)
      n_theta_loc = n_theta_dist(coord_theta,2) - n_theta_dist(coord_theta,1)+1
      
      if (rank == 0) then
         print "('θ partition in rank ', I3, ': ', I5, I5, I5, ' points')", &
               0, n_theta_dist(0,1), n_theta_dist(0,2), n_theta_dist(0,2) - &
               n_theta_dist(0,1) + 1
         do i=1, n_ranks_theta-1
            print "('               rank ', I3, ': ', I5, I5, I5, ' points')", &
                  i, n_theta_dist(i,1), n_theta_dist(i,2), n_theta_dist(i,2) - &
                  n_theta_dist(i,1) + 1
         end do
      end if
      
      ! Deals with lmP_dist and lm_dist (for radial loop)
      !---------------------------------------------------
      n_m_ext = ceiling(real(m_max+1)/real(minc*n_ranks_theta))
      
      allocate(lmP_dist(0:n_ranks_theta-1, n_m_ext, 4))
      allocate(lm_dist(0:n_ranks_theta-1, n_m_ext, 4))
      
      call distribute_snake_old(lmP_dist, l_max+1, m_max, minc)
      call distribute_snake_old(lm_dist,  l_max  , m_max, minc)
      
      n_m_loc = n_m_ext - 1
      if (lmP_dist(coord_theta,n_m_ext,1) > -1) n_m_loc = n_m_ext
      
      if (rank == 0) then
         do i=0, n_ranks_theta-1
            do j=1, n_m_ext
               print "('lmP partition in rank ', I3, ': ', I5, I5, I5, I5)", i,&
               lmP_dist(i,j,1:4)
            end do
            print "('length in rank ', I3, ' is ', I5)", i, sum(lmP_dist(i,:,2))
         end do
      end if
      
      ! Deals with lo_dist (for MLLoop)
      !---------------------------------------------------
!       n_lo_ext = ceiling(real(l_max+1)/real(n_ranks_theta))
!       
!       allocate(lo_dist(0:n_ranks_theta, n_lo_ext, 0:n_m_max))
!       
!       call distribute_lo_simple(lo_dist,l_max, m_max, minc)
!       
!       if (rank ==0) then
!          do proc_idx=0, n_ranks_theta-1
!             print *, "=======================>", proc_idx
!             do i=1, n_lo_ext
!                print *, "---------------->", lo_dist(proc_idx, i, 0)
!                print *, lo_dist(proc_idx, i, 1:n_m_max)
!             end do
!          end do
!       end if
!       
!       stop
      
      
      ! Sets some shortcuts
      !---------------------------------------------------
      lmP_loc = sum(lmP_dist(coord_theta,:,2))
      lm_loc  = sum(lm_dist( coord_theta,:,2))
      lm_locMag = lm_loc
      lm_locChe = lm_loc
      lm_locTP  = lm_loc
      lm_locDC  = lm_loc
      if ( lm_maxMag==1 ) lm_locMag = 1
      if ( .not. l_chemical_conv ) lm_locChe = 1
      if ( .not. l_TP_form       ) lm_locTP  = 1
      if ( .not. l_double_curl   ) lm_locDC  = 1
      
   end subroutine distribute_truncation
   
   !----------------------------------------------------------------------------   
   subroutine distribute_round_robin(idx_dist, l_max, m_max, minc)
      !
      !   This will try to create a balanced workload, by assigning to each 
      !   rank  non-consecutive m points. For instance, if we have m_max=16, minc=1 and 
      !   n_ranks_theta=4, we will have:
      !   
      !   rank 0: 0, 4,  8, 12, 16
      !   rank 1: 1, 5,  9, 13
      !   rank 2: 2, 6, 10, 14
      !   rank 3: 3, 7, 11, 15
      !   
      !   This is not optimal, but seem to be a decent compromise.
      ! 
      !   Author: Rafael Lago, MPCDF, December 2017
      !
      integer, intent(inout) :: idx_dist(0:n_ranks_theta-1, n_m_ext, 4)
      integer, intent(in)    :: l_max, m_max, minc
      
      integer :: m_idx, proc_idx, row_idx
      
      idx_dist        = -minc
      idx_dist(:,:,2) =  0
      idx_dist(:,1,3) =  1
      
      m_idx=0
      row_idx = 1
      do while (m_idx <= m_max)
         do proc_idx=0, n_ranks_theta-1
            idx_dist(proc_idx, row_idx, 1) = m_idx
            idx_dist(proc_idx, row_idx, 2) = l_max - m_idx + 1
            if (row_idx > 1) idx_dist(proc_idx, row_idx, 3) = &
                             idx_dist(proc_idx, row_idx-1, 4) + 1
            idx_dist(proc_idx, row_idx, 4) = idx_dist(proc_idx, row_idx, 3) &
                                           + l_max - m_idx
            
            m_idx = m_idx + minc
            if (m_idx > m_max) exit
         end do
         row_idx = row_idx + 1
      end do
     
   end subroutine distribute_round_robin
   
   !----------------------------------------------------------------------------   
   subroutine distribute_snake_old(idx_dist, l_max, m_max, minc)
      !   
      !   Same as above but for Snake Ordering
      !   
      !   Author: Rafael Lago, MPCDF, December 2017
      !
      integer, intent(inout) :: idx_dist(0:n_ranks_theta-1, n_m_ext, 4)
      integer, intent(in)    :: l_max, m_max, minc
      
      integer :: m_idx, proc_idx, row_idx
      
      idx_dist        = -minc
      idx_dist(:,:,2) =  0
      idx_dist(:,1,3) =  1
      
      m_idx=0
      row_idx = 1
      do while (m_idx <= m_max)
         do proc_idx=0, n_ranks_theta-1
            idx_dist(proc_idx, row_idx, 1) = m_idx
            idx_dist(proc_idx, row_idx, 2) = l_max - m_idx + 1
            if (row_idx > 1) idx_dist(proc_idx, row_idx, 3) = &
                             idx_dist(proc_idx, row_idx-1, 4) + 1
            idx_dist(proc_idx, row_idx, 4) = idx_dist(proc_idx, row_idx, 3) &
                                           + l_max - m_idx
            m_idx = m_idx + minc
            if (m_idx > m_max) exit
         end do
         row_idx = row_idx + 1
         do proc_idx=n_ranks_theta-1,0,-1
            if (m_idx > m_max) exit
            idx_dist(proc_idx, row_idx, 1) = m_idx
            idx_dist(proc_idx, row_idx, 2) = l_max - m_idx + 1
            if (row_idx > 1) idx_dist(proc_idx, row_idx, 3) = &
                             idx_dist(proc_idx, row_idx-1, 4) + 1
            idx_dist(proc_idx, row_idx, 4) = idx_dist(proc_idx, row_idx, 3) &
                                           + l_max - m_idx
            
            m_idx = m_idx + minc
         end do
         row_idx = row_idx + 1
      end do
      
     
   end subroutine distribute_snake_old
   
!    !----------------------------------------------------------------------------
!    subroutine distribute_lo_simple(idx_dist, l_max, m_max, minc)
!       !   This is a simplified version of the future lo distribution.
!       !          
!       !   At this point it will just use snake ordering to distribute the l's
!       !   and then after it will assign all m's to that l. For many 
!       !   configurations, this function won't work.
!       !          
!       !   Author: Rafael Lago, MPCDF, December 2017
!       !
!       integer, intent(inout) :: idx_dist(0:n_ranks_theta, n_lo_ext, 0:n_m_max)
!       integer, intent(in)    :: l_max, m_max, minc
!       
!       integer :: proc_idx, i, j, l_idx, m_idx
!       
!       idx_dist = -1
!       
!       l_idx=0
!       i = 1
!       
!       ! Distribute l's (snake ordering)
!       !----------------------------------------
!       do while (l_idx <= l_max)
!          do proc_idx=0, n_ranks_theta-1
!             idx_dist(proc_idx, i, 0) = l_idx
!             l_idx = l_idx + 1
!             if (l_idx > l_max) exit
!          end do
!          i = i + 1
!          do proc_idx=n_ranks_theta-1,0,-1
!             if (l_idx > l_max) exit
!             idx_dist(proc_idx, i, 0) = l_idx
!             l_idx = l_idx + 1
!          end do
!          i = i + 1
!       end do
!       
!       ! Distribute m's for each l
!       ! This is a naïve distribution; each l will be assigned 
!       ! all of its  m's
!       !---------------------------------------------------------------
!       do proc_idx=0, n_ranks_theta-1
!          do i=1, n_lo_ext
!             l_idx = idx_dist(proc_idx, i, 0)
!             if (l_idx < 0) exit
!             j = 1
!             do m_idx = 0, l_idx, minc
!                idx_dist(proc_idx, i, j) = m_idx
!                j = j + 1
!             end do
!          end do
!       end do
!       
!    end subroutine distribute_lo_simple
   
   !----------------------------------------------------------------------------
   subroutine checkTruncation
      !
      !  This function checks truncations and writes it
      !  into STDOUT and the log-file.                                 
      !  MPI: called only by the processor responsible for output !  
      !  

      if ( minc < 1 ) then
         call abortRun('! Wave number minc should be > 0!')
      end if
      if ( mod(n_phi_tot,minc) /= 0 .and. (.not. l_axi) ) then
         call abortRun('! Number of longitude grid points n_phi_tot must be a multiple of minc')
      end if
      if ( mod(n_phi_max,4) /= 0 .and. (.not. l_axi) ) then
         call abortRun('! Number of longitude grid points n_phi_tot/minc must be a multiple of 4')
      end if
      if ( mod(n_phi_tot,16) /= 0 .and. (.not. l_axi) ) then
         call abortRun('! Number of longitude grid points n_phi_tot must be a multiple of 16')
      end if
      if ( n_phi_max/2 <= 2 .and. (.not. l_axi) ) then
         call abortRun('! Number of longitude grid points n_phi_tot must be larger than 2*minc')
      end if

      !-- Checking radial grid:
      if ( .not. l_finite_diff ) then
         if ( mod(n_r_max-1,4) /= 0 ) then
            call abortRun('! Number n_r_max-1 should be a multiple of 4')
         end if
      end if

      if ( n_theta_max <= 2 ) then
         call abortRun('! Number of latitude grid points n_theta_max must be larger than 2')
      end if
      if ( mod(n_theta_max,4) /= 0 ) then
         call abortRun('! Number n_theta_max of latitude grid points be a multiple must be a multiple of 4')
      end if
      if ( n_cheb_max > n_r_max ) then
         call abortRun('! n_cheb_max should be <= n_r_max!')
      end if
      if ( n_cheb_max < 1 ) then
         call abortRun('! n_cheb_max should be > 1!')
      end if
      if ( (n_phi_max+1)*n_theta_max > lm_max_real*(n_r_max+2) ) then
         call abortRun('! (n_phi_max+1)*n_theta_max > lm_max_real*(n_r_max+2) !')
      end if

   end subroutine checkTruncation
   !----------------------------------------------------------------------------   
   subroutine distribute_discontiguous_snake(dist, max_len, N, p)
      !  
      !  Distributes N points amongst p ranks using snake ordering.
      !  max_len is supposed to be the ceiling(N/p)
      !  
      integer, intent(in)    :: max_len, N, p
      integer, intent(inout) :: dist(0:p-1, 0:max_len)
      
      integer :: j, ipt, irow
      
      dist(:,:) =  -1
      ipt  = 1
      irow = 1
      
      do while (.TRUE.)
         do j=0, p-1
            dist(j, irow) = ipt
            ipt = ipt + 1
            if (ipt > N) return
         end do
         irow = irow + 1
         do j=p-1,0,-1
            dist(j, irow) = ipt
            ipt = ipt + 1
            if (ipt > N) return
         end do
         irow = irow + 1
      end do
   end subroutine distribute_discontiguous_snake
   !----------------------------------------------------------------------------   
   subroutine distribute_discontiguous_roundrobin(dist, max_len, N, p)
      !  
      !  Distributes N points amongst p ranks using round Robin ordering.
      !  max_len is supposed to be the ceiling(N/p)
      !  
      integer, intent(in)    :: max_len, N, p
      integer, intent(inout) :: dist(0:p-1, 0:max_len)
      
      integer :: j, ipt, irow
      
      dist(:,:) =  -1
      ipt  = 1
      irow = 1
      
      do while (.TRUE.)
         do j=0, p-1
            dist(j, irow) = ipt
            ipt = ipt + 1
            if (ipt > N) return
         end do
         irow = irow + 1
      end do
   end subroutine distribute_discontiguous_roundrobin
   
   !-------------------------------------------------------------------------------
   subroutine distribute_contiguous_first(dist,N,p)
      !  
      !  Distributes N points amongst p ranks. If N is not divisible by p, add
      !  one extra point in the first ranks (thus, "front")
      !  
      integer, intent(in) :: p
      integer, intent(in) :: N
      integer, intent(out) :: dist(0:p-1,0:2)
      
      integer :: rem, loc, i
      
      loc = N/p
      rem = N - loc*p
      do i=0,p-1
         dist(i,1) = loc*i + min(i,rem) + 1
         dist(i,2) = loc*(i+1) + min(i+1,rem)
      end do
   end subroutine distribute_contiguous_first
   !-------------------------------------------------------------------------------
   subroutine distribute_contiguous_last(dist,N,p)
      !  
      !  Like above, but extra points go in the last ranks instead of 
      !  the first ranks
      !  
      integer, intent(in) :: p
      integer, intent(in) :: N
      integer, intent(out) :: dist(0:p-1,0:2)
      
      integer :: rem, loc, i
      
      loc = N/p
      rem = N - loc*p
      do i=0,p-1
         dist(i,1) = loc*i + max(i+rem-p,0) + 1
         dist(i,2) = loc*(i+1) + max(i+rem+1-p,0)
      end do
   end subroutine distribute_contiguous_last
   
   !-------------------------------------------------------------------------------
   subroutine print_contiguous_distribution(dist,p,name)
      !  
      !  Cosmetic function to display the distributio of the points
      !  
      integer, intent(in) :: p
      integer, intent(in) :: dist(0:p-1,0:2)
      character(*), intent(in) :: name
      integer :: i
      
      if (rank /= 0) return
      
      print "(' ! ',A,' partition in rank ', I0, ': ', I0,'-',I0, '  (', I0, ' pts)')", name, &
            0, dist(0,1), dist(0,2), dist(0,0)
            
      do i=1, p-1
         print "(' !                rank ', I0, ': ', I0,'-',I0, '  (', I0, ' pts)')", &
               i, dist(i,1), dist(i,2), dist(i,0)
      end do
   end subroutine print_contiguous_distribution
   
   !-------------------------------------------------------------------------------
   subroutine print_discontiguous_distribution(dist,max_len,p,name)
      !  
      !  Cosmetic function to display the distributio of the points
      !  
      integer, intent(in) :: max_len, p
      integer, intent(in) :: dist(0:p-1,0:max_len)
      character(*), intent(in) :: name
      
      integer :: i, j, counter
      
      if (rank /= 0) return
      
      do i=0, n_ranks_theta-1
         write (*,'(A,I0,A,I0)', ADVANCE='NO') ' ! '//name//' partition in rank ', i, ' :', dist(i,1)
         counter = 1
         do j=2, dist(i,0)
            write (*, '(A,I0)', ADVANCE='NO') ',', dist(i,j)
         end do
         write (*, '(A,I0,A)') "  (",dist(i,0)," pts)"
      end do
   end subroutine print_discontiguous_distribution

end module truncation
