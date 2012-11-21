!###############################################################
!     PURPOSE  : Constructs some functions used in other places. 
!     AUTHORS  : Adriano Amaricci
!###############################################################
module UPDATE_WF
  USE MATRIX
  USE VARS_GLOBAL
  implicit none
  private

  public                           :: neq_update_weiss_field

contains


  !+-------------------------------------------------------------------+
  !PURPOSE  : Update the Weiss Fields G0^{>,<,Ret} using Dyson equation
  !+-------------------------------------------------------------------+
  subroutine neq_update_weiss_field
    integer :: M,i,j,k,itau,jtau,NN
    real(8) :: R,deg
    real(8) :: w,A,An
    complex(8),dimension(0:nstep,0:nstep) :: locGret,Sret
    complex(8),dimension(0:nstep,0:nstep) :: locGadv,Sadv
    complex(8),dimension(0:nstep,0:nstep) :: Uno,GammaRet
    complex(8),dimension(0:nstep,0:nstep) :: G0ret
    complex(8),dimension(0:nstep,0:nstep) :: G0adv
    !
    complex(8),dimension(:,:),allocatable :: mat_Delta
    complex(8),dimension(:,:),allocatable :: mat_Gamma
    complex(8),dimension(:,:),allocatable :: mat_G0,mat_Sigma,mat_locG
    !
    type(keldysh_contour_gf),save             :: G0_old

    if(G0_old%status.EQV..false.)call allocate_keldysh_contour_gf(G0_old,Nstep)
    G0_old=G0    

    call msg("Update WF: Dyson")
    if(update_wfftw)then
       call update_equilibrium_weiss_field
    else
       include "update_G0_nonequilibrium.f90"
    endif
    G0%less = weight*G0%less + (1.d0-weight)*G0_old%less
    G0%gtr  = weight*G0%gtr  + (1.d0-weight)*G0_old%gtr

    !Save data:
    if(mpiID==0)then
       call write_keldysh_contour_gf(G0,trim(data_dir)//"/G0")
       if(plot3D)call plot_keldysh_contour_gf(G0,t(0:),trim(plot_dir)//"/G0")
    end if
  end subroutine neq_update_weiss_field



  !********************************************************************
  !********************************************************************
  !********************************************************************

  function build_keldysh_matrix_gf(G,N) result(matG)
    type(keldysh_contour_gf)              :: G
    complex(8),dimension(0:2*N+1,0:2*N+1) :: matG
    integer                               :: i,j,N
    forall(i=0:N,j=0:N)
       matG(i,j)         = step(t(i)-t(j))*G%gtr(i,j) + step(t(j)-t(i))*G%less(i,j)
       matG(i,N+1+j)     =-G%less(i,j)
       matG(N+1+i,j)     = G%gtr(i,j)
       matG(N+1+i,N+1+j) =-(step(t(i)-t(j))*G%less(i,j)+ step(t(j)-t(i))*G%gtr(i,j))
    end forall
  end function build_keldysh_matrix_gf


  !********************************************************************
  !********************************************************************
  !********************************************************************


  subroutine update_equilibrium_weiss_field
    integer :: M,i,j,k,itau,jtau,NN
    real(8) :: R,deg
    real(8) :: w,A,An
    forall(i=0:nstep,j=0:nstep)
       gf%ret%t(i-j) = heaviside(t(i-j))*(locG%gtr(i,j)-locG%less(i,j))
       sf%ret%t(i-j) = heaviside(t(i-j))*(Sigma%gtr(i,j)-Sigma%less(i,j))
    end forall
    if(heaviside(0.d0)==1.d0)gf%ret%t(0)=gf%ret%t(0)/2.d0
    if(heaviside(0.d0)==1.d0)sf%ret%t(0)=sf%ret%t(0)/2.d0

    call fftgf_rt2rw(gf%ret%t,gf%ret%w,nstep) ; gf%ret%w=gf%ret%w*dt ; call swap_fftrt2rw(gf%ret%w)
    call fftgf_rt2rw(sf%ret%t,sf%ret%w,nstep) ; sf%ret%w=sf%ret%w*dt ; call swap_fftrt2rw(sf%ret%w)
    gf0%ret%w  = one/(one/gf%ret%w + sf%ret%w)
    gf0%less%w = less_component_w(gf0%ret%w,wr,beta)
    gf0%gtr%w  = gtr_component_w(gf0%ret%w,wr,beta)
    ! call splot("updateG0ret_w.ipt",wr,gf0%ret%w,append=TT)
    ! call splot("updateG0less_w.ipt",wr,gf0%less%w,append=TT)
    ! call splot("updateG0gtr_w.ipt",wr,gf0%gtr%w,append=TT)

    call fftgf_rw2rt(gf0%less%w,gf0%less%t,nstep) ; gf0%less%t=exa*fmesh/pi2*gf0%less%t
    call fftgf_rw2rt(gf0%gtr%w, gf0%gtr%t,nstep)  ; gf0%gtr%t =exa*fmesh/pi2*gf0%gtr%t
    call fftgf_rw2rt(gf0%ret%w, gf0%ret%t,nstep)  ; gf0%ret%t =exa*fmesh/pi2*gf0%ret%t
    forall(i=0:nstep,j=0:nstep)
       G0%less(i,j)= gf0%less%t(i-j)
       G0%gtr(i,j) = gf0%gtr%t(i-j)
    end forall
    ! call splot("updateG0ret_t.ipt",t,gf0%ret%t,append=TT)
    ! call splot("G0less3D",t(0:nstep)/dt,t(0:nstep)/dt,G0less(0:nstep,0:nstep))
    ! call splot("G0gtr3D",t(0:nstep)/dt,t(0:nstep)/dt,G0gtr(0:nstep,0:nstep))

    ! !PLus this:
    ! forall(i=0:nstep,j=0:nstep)
    !    G0ret(i,j)=heaviside(t(i-j))*(G0gtr(i,j) - G0less(i,j))
    !    gf0%ret%t(i-j)=G0ret(i,j)
    ! end forall
    ! call fftgf_rt2rw(gf0%ret%t,gf0%less%w,nstep) ; gf0%less%w=gf0%less%w*dt ; call swap_fftrt2rw(gf0%less%w)
  end subroutine update_equilibrium_weiss_field




  ! !+-------------------------------------------------------------------+
  ! !PURPOSE  : Build a guess for the initial Weiss Fields G0^{<,>} 
  ! !as non-interacting GFs. If required read construct it starting 
  ! !from a read seed (cf. routine for seed reading)
  ! !+-------------------------------------------------------------------+
  ! subroutine neq_guess_weiss_field
  !   integer    :: i,j,ik,redLk
  !   real(8)    :: en,intE,A
  !   complex(8) :: peso
  !   real(8)    :: nless,ngtr

  !   call msg("Get G0guess(t,t')",id=0)
  !   gf0=zero ; G0gtr=zero ; G0less=zero
  !   if(mpiID==0)then

  !      if(irdeq .OR. solve_eq)then            !Read from equilibrium solution
  !         call read_init_seed()
  !         do ik=1,irdL             !2*L
  !            en   = irdwr(ik)
  !            nless= fermi0(en,beta)
  !            ngtr = fermi0(en,beta)-1.d0
  !            A    = -aimag(irdG0w(ik))/pi*irdfmesh
  !            do i=-nstep,nstep
  !               peso=exp(-xi*en*t(i))
  !               gf0%less%t(i)=gf0%less%t(i) + xi*nless*A*peso
  !               gf0%gtr%t(i) =gf0%gtr%t(i)  + xi*ngtr*A*peso
  !            enddo
  !         enddo
  !         forall(i=0:nstep,j=0:nstep)
  !            G0less(i,j)=gf0%less%t(i-j)
  !            G0gtr(i,j) =gf0%gtr%t(i-j)
  !         end forall

  !      else

  !         if(equench)then
  !            do ik=1,Lk
  !               en   = epsik(ik)
  !               nless= fermi0(en,beta)
  !               ngtr = fermi0(en,beta)-1.d0
  !               do j=0,nstep
  !                  do i=0,nstep
  !                     intE=int_Ht(ik,i,j)
  !                     peso=exp(-xi*intE)
  !                     G0less(i,j)= G0less(i,j) + xi*nless*peso*wt(ik)
  !                     G0gtr(i,j) = G0gtr(i,j)  + xi*ngtr*peso*wt(ik)
  !                  enddo
  !               enddo
  !            enddo

  !         else

  !            do ik=1,Lk
  !               en   = epsik(ik)
  !               nless= fermi0(en,beta)
  !               ngtr = fermi0(en,beta)-1.d0
  !               A    = wt(ik)
  !               do i=-nstep,nstep
  !                  peso=exp(-xi*en*t(i))
  !                  gf0%less%t(i)=gf0%less%t(i) + xi*nless*A*peso
  !                  gf0%gtr%t(i) =gf0%gtr%t(i)  + xi*ngtr*A*peso
  !               enddo
  !            enddo
  !            forall(i=0:nstep,j=0:nstep)
  !               G0less(i,j)=gf0%less%t(i-j)
  !               G0gtr(i,j) =gf0%gtr%t(i-j)
  !            end forall

  !         endif
  !      endif

  !      call splot("guessG0less.data",G0less(0:nstep,0:nstep))
  !      call splot("guessG0gtr.data",G0gtr(0:nstep,0:nstep))
  !   endif
  !   call MPI_BCAST(G0less,(nstep+1)*(nstep+1),MPI_DOUBLE_COMPLEX,0,MPI_COMM_WORLD,mpiERR)
  !   call MPI_BCAST(G0gtr,(nstep+1)*(nstep+1),MPI_DOUBLE_COMPLEX,0,MPI_COMM_WORLD,mpiERR)

  ! contains

  !   function int_Ht(ik,it,jt)
  !     real(8)      :: int_Ht
  !     integer      :: i,j,ii,ik,it,jt,sgn
  !     type(vect2D) :: kt,Ak
  !     int_Ht=0.d0 ; if(it==jt)return
  !     sgn=1 ; if(jt > it)sgn=-1
  !     i=ik2ix(ik); j=ik2iy(ik)
  !     do ii=jt,it,sgn
  !        Ak=Afield(t(ii),Ek)
  !        kt=kgrid(i,j) - Ak
  !        int_Ht=int_Ht + sgn*square_lattice_dispersion(kt)*dt
  !     enddo
  !   end function int_Ht

  ! end subroutine neq_guess_weiss_field




  !********************************************************************
  !********************************************************************
  !********************************************************************



  ! !+-------------------------------------------------------------------+
  ! !PURPOSE  : Build a guess for the initial Weiss Fields G0^{<,>} 
  ! !as non-interacting GFs. If required construct it starting 
  ! !from a read seed (cf. routine for seed reading)
  ! !+-------------------------------------------------------------------+
  ! subroutine read_init_seed()
  !   logical :: control
  !   real(8) :: w1,w2
  !   integer :: ik,redLk
  !   real(8),allocatable :: rednk(:),redek(:)
  !   integer,allocatable :: orderk(:)
  !   real(8),allocatable :: uniq_rednk(:),uniq_redek(:)
  !   logical,allocatable :: maskk(:)

  !   !GO_realw:
  !   inquire(file=trim(irdG0file),exist=control)
  !   if(.not.control)call error("Can not find irdG0file")
  !   !Read the function WF
  !   irdL=file_length(trim(irdG0file))
  !   allocate(irdG0w(irdL),irdwr(irdL))
  !   call sread(trim(irdG0file),irdwr,irdG0w)
  !   !Get G0 mesh:
  !   irdfmesh=abs(irdwr(2)-irdwr(1))

  !   !n(k): A lot of work here to reshape the array
  !   inquire(file=trim(irdnkfile),exist=control)
  !   if(.not.control)call abort("Can not find irdnkfile")
  !   !Read the function nk.
  !   redLk=file_length(trim(irdnkfile))
  !   allocate(rednk(redLk),redek(redLk),orderk(redLk))
  !   call sread(trim(irdnkfile),redek,rednk)
  !   !work on the read arrays:
  !   !1 - sorting: sort the energies (X-axis), mirror on occupation (Y-axis) 
  !   !2 - delete duplicates energies (X-axis), mirror on occupation (Y-axis) 
  !   !3 - interpolate to the actual lattice structure (epsik,nk)
  !   call sort_array(redek,orderk)
  !   call reshuffle(rednk,orderk)
  !   call uniq(redek,uniq_redek,maskk)
  !   allocate(uniq_rednk(size(uniq_redek)))
  !   uniq_rednk = pack(rednk,maskk)
  !   allocate(irdnk(Lk))
  !   call linear_spline(uniq_rednk,uniq_redek,irdnk,epsik)

  !   !G0_iw:
  !   allocate(irdG0iw(L),irdG0tau(0:Ltau))
  !   call get_matsubara_gf_from_DOS(irdwr,irdG0w,irdG0iw,beta)
  !   call fftgf_iw2tau(irdG0iw,irdG0tau,beta)


  !   !Print out the initial conditions as effectively read from the files:
  !   call system("if [ ! -d InitialConditions ]; then mkdir InitialConditions; fi")
  !   call splot("InitialConditions/read_G0_realw.ipt",irdwr,irdG0w)
  !   call splot("InitialConditions/read_G0_iw.ipt",irdwm,irdG0iw)
  !   call splot("InitialConditions/read_G0_tau.ipt",tau,irdG0tau)
  !   call splot("InitialConditions/read_nkVSek.ipt",epsik,irdnk)

  !   call MPI_BCAST(irdG0w,irdL,MPI_DOUBLE_COMPLEX,0,MPI_COMM_WORLD,mpiERR)
  !   call MPI_BCAST(irdG0iw,irdL,MPI_DOUBLE_COMPLEX,0,MPI_COMM_WORLD,mpiERR)
  !   call MPI_BCAST(irdG0tau,Ltau+1,MPI_DOUBLE_COMPLEX,0,MPI_COMM_WORLD,mpiERR)
  !   call MPI_BCAST(irdNk,Lk,MPI_DOUBLE_PRECISION,0,MPI_COMM_WORLD,mpiERR)
  ! end subroutine read_init_seed




  !********************************************************************
  !********************************************************************
  !********************************************************************





end module UPDATE_WF