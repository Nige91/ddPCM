!> @copyright (c) 2020-2021 RWTH Aachen. All rights reserved.
!!
!! ddX software
!!
!! @file tests/main.f90
!! Main ddx driver.
!!
!! @version 1.0.0
!! @author Aleksandr Mikhalev
!! @date 2021-02-11

program main
use dd_core
use dd_operators
use dd_solvers
use dd_cosmo
use dd_pcm
implicit none

character(len=255) :: fname
type(dd_data_type) :: dd_data
integer :: info
real(dp), allocatable :: phi(:), gradphi(:, :), psi(:, :)
real(dp) :: start_time, finish_time
integer :: i, j

! Read input file name
call getarg(1, fname)
write(*, *) "Using provided file ", trim(fname), " as a config file"
call ddfromfile(fname, dd_data, info)
if(info .ne. 0) stop "info != 0"
allocate(phi(dd_data % ncav), gradphi(3, dd_data % ncav), &
    & psi(dd_data % nbasis, dd_data % nsph))
call cpu_time(start_time)
call mkrhs(dd_data, phi, gradphi, psi)
call cpu_time(finish_time)
write(*, "(A,ES11.4E2,A)") "MKRHS time:", finish_time-start_time, " seconds"
call cpu_time(start_time)
call ddpcm(dd_data, phi, psi)
call cpu_time(finish_time)
write(*, "(A,ES11.4E2,A)") "DDPCM time:", finish_time-start_time, " seconds"
deallocate(phi, gradphi, psi)
call ddfree(dd_data)

end program main

