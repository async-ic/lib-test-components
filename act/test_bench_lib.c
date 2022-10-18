/*************************************************************************
 *
 *
 * Copyright 2022 Ole Richter - University of Groningen
 * Copyright 2022 Michele Mastella - University of Groningen
 *
 *  This program is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU General Public License
 *  as published by the Free Software Foundation; either version 2
 *  of the License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor,
 *  Boston, MA  02110-1301, USA.
 *
 **************************************************************************
 */

/**
* this file contains all the helper fucntions to read the CSV test benches.
*/


#include <stdio.h>
#include <stdlib.h>
#include <act/actsim_ext.h>

/**
* the arrays are staticly allocated, like how many sources aor checks there are, they can be easily increased and recompiled
* the defaults are thought to be fine for most smaller test benches
* also the standard file naming and that the csv is using a ; as seperator can be changed
*/

#define MAX_SOURCES 100
#define MAX_CHECKERS 100
#define MAX_CHECKS 100000
#define MAX_DUMP 100
#define CSV_FORMAT "%u; %lu"
#define CSV_WRITE_FORMAT "%d; %d\n"
#define SOURCE_FILENAME "source_%d.csv"
#define CHECK_FILENAME "check_%d.csv"
#define DUMP_FILENAME "dump_%d.csv"
#define CONTROL_FILENAME "control.csv"
#define LOG_FILENAME "test_bench_helper.log"

/**
* as the testbench is calling the functions, all state variables need to be static so they are the same state whenever called
*
*/

// all opened files for the text bench
static FILE *source_file[MAX_SOURCES];
static FILE *check_file[MAX_CHECKERS];
static FILE *dump_file[MAX_DUMP];
static FILE *control_file;

// the data variable buffers, as we can only deliver one variable at a time,
// so first is there a variable and than the varibale itself
static unsigned int source_sim_step[MAX_SOURCES];
static unsigned int check_sim_step[MAX_CHECKERS];
static unsigned long source_data_buffer[MAX_SOURCES];
static unsigned long check_data_buffer[MAX_CHECKERS][MAX_CHECKS];
static unsigned short check_data_used[MAX_CHECKERS][MAX_CHECKS];
static unsigned int check_data_number[MAX_CHECKERS];

// as printing does not get dispayed in actsim, print to logfile
static FILE *logfile = NULL;

// show more info like words/tests read
static int verbose = 0;

// keep a memory at which simulation step we are in the files
static unsigned long last_sim_step = 0;
static unsigned int first_sim_step = 0;
static unsigned long current_sim_step = 0;
static unsigned long current_sim_wait = 1;
static unsigned int check_errors = 0;

/**
* Init opens all the files and reads the control
* it requires one int:
* verbose: 0 for normal pinting, 1 for verbose printing
* it returns true on success
*/
struct expr_res init (int num, struct expr_res *args)
{
  struct expr_res t;
  t.v = 0;
  t.width = 1;
  check_errors = 0;
  logfile = fopen(LOG_FILENAME, "w");
  if (num !=1 ){
    fprintf(logfile,"[ERROR] wrong number of arguments in init"); fflush(logfile);
    return t;
  }
  verbose = args[0].v;
  fprintf(logfile,"==== initialising control ====\n"); fflush(logfile);
  control_file = fopen (CONTROL_FILENAME, "r");
  int success = 0;
  success = fscanf(control_file, CSV_FORMAT, &first_sim_step, &last_sim_step);
  if (success != 2) {
    if(ferror(source_file[args[0].v])){
      fprintf(logfile,"read error on control\n"); fflush(logfile);
      return t;
    } 
    else {
      fprintf(logfile,"empty file for control\n"); fflush(logfile);
      return t;
    }
  }

  fprintf(logfile,"==== initialising source ====\n"); fflush(logfile);
  int i = 0;
  for (i = 0; i<MAX_SOURCES; i++){
    source_sim_step[i] = 0;
    char filename[255];
    snprintf(filename, 255, SOURCE_FILENAME,i);
    source_file[i] = fopen (filename, "r");
    if (source_file[i]){
      fprintf(logfile, "source id %d -> %s\n",i,filename); fflush(logfile);
    }
  }
  fprintf(logfile,"==== initialising check ====\n"); fflush(logfile);
  
  for (i = 0; i<MAX_CHECKERS; i++){
    check_sim_step[i] = 0;
    char filename[255];
    snprintf(filename, 255, CHECK_FILENAME,i);
    check_file[i] = fopen (filename, "r");
    if (check_file[i]){
      fprintf(logfile, "check id %d -> %s\n",i,filename); fflush(logfile);
    }
  }
  fprintf(logfile,"==== initialising done ====\n"); fflush(logfile);
  t.v = 1;
  return t;
}

/**
* check_next looks if there is an other check availible in that simulation step
* if a new simulation step is loaded all checks from this step will be cashed into the arrays
* it requires 2 int:
* id: the id of the checker
* simstep: the simulation step the next test to be loaded from
* it returns 1 if there is a check availible, 0 if not or an error occured
*/
struct expr_res check_next (int num, struct expr_res *args){
  struct expr_res t;
  t.v = 0 ;
  t.width = 1;
  if (num !=2 ){
    fprintf(logfile,"[ERROR] wrong number of arguments in channel_check\n"); fflush(logfile);
    return t;
  }
  if (!check_file[args[0].v]) { 
    fprintf(logfile,"[ERROR] could not read check %d, file not open or does not exist\n",args[0].v); fflush(logfile);
    return t;
  }
  int step_done = 0, i = 0;
  unsigned int check_sim_step_file = 0;
  unsigned long int sim_data_file = 0;
  // check if we need to advnce one step
  if (check_sim_step[args[0].v] != args[1].v){
    // print all missed steps
    for (i = 0; i < check_data_number[args[0].v]; i++){
      if (check_data_used[args[0].v][i] == 0) {
          check_errors++;
          fprintf(logfile,"[FAILURE] missed %d on check %d - %d for simstep %d; Error count: %d\n",check_data_buffer[args[0].v],args[0].v,i,check_sim_step[args[0].v],check_errors); fflush(logfile);
      }
    }
    // load next step
    rewind(check_file[args[0].v]);
    check_sim_step[args[0].v] = args[1].v;
    unsigned int count = 0;
    // read next steps
    while (!step_done){
      int success = 0;
      success = fscanf(check_file[args[0].v], CSV_FORMAT, &check_sim_step_file, &sim_data_file);
      if (success != 2) {
        if(ferror(check_file[args[0].v])) fprintf(logfile,"read error on check %d\n",args[0].v);
        if(verbose) fprintf(logfile,"EOF on check %d\n",args[0].v); fflush(logfile);
        step_done = 1;
      }
      else if (count >= MAX_CHECKS) {
        fprintf(logfile,"[ERROR] checks for sim step %d on checker %d, exceed the maximum number of checks, increase and recompile\n",args[0].v); fflush(logfile);
      }
      else if (check_sim_step_file == check_sim_step[args[0].v]){
        check_data_buffer[args[0].v][count] = sim_data_file;
        check_data_used[args[0].v][count] = 0;
        if(verbose) fprintf(logfile,"%d check %d on %d\n",count,check_data_buffer[args[0].v][count],args[0].v); fflush(logfile);
        count++;
      }
    }
    check_data_number[args[0].v] = count;
  }
  // check if any checks have not been used yet 
  for (i = 0; i < check_data_number[args[0].v]; i++){
    if (check_data_used[args[0].v][i] == 0) {
      t.v = 1 ;
      i = check_data_number[args[0].v];
      break;
    }
  }
  return t;
}

/**
* check_in_order compares a word to the next avaible word in the csv,
* check_next has to be called before 
* it requres 2 ints:
* id: the id of the checker
* word to check: the word to compare
* returns 1 on success and 0 on failure
*/
struct expr_res check_in_order (int num, struct expr_res *args)
{
  struct expr_res t;
  t.v = 0 ;
  t.width = 0;
  if (num !=2 ){
    fprintf(logfile,"[ERROR] wrong number of arguments in channel_check\n");
    return t;
  }
  for (int i = 0; i < check_data_number[args[0].v]; i++){
    if (check_data_used[args[0].v][i] == 0) {
      if (check_data_buffer[args[0].v][i] == args[1].v){
        fprintf(logfile,"[SUCCESS] got %d = %d on check %d - %d\n",check_data_buffer[args[0].v],args[1].v,args[0].v,i); fflush(logfile);
        t.v = 1;
      }
      else {
        check_errors++;
        fprintf(logfile,"[FAILURE] expected %d got %d on check %d - %d; Error count %d\n",check_data_buffer[args[0].v],args[1].v,args[0].v,i,check_errors); fflush(logfile);
        t.v = 0;
      }
      check_data_used[args[0].v][i] = 1;
      i = check_data_number[args[0].v];
      break;
    }
  }
  
  t.width = 1;
  return t; 
}

/**
* check_out_of_order compares a word to the all avaible word in the csv for that step,
* each word can only be used once.
* check_next has to be called before 
* it requres 2 ints:
* id: the id of the checker
* word to check: the word to compare
* returns 1 on success and 0 on failure
*/
struct expr_res check_out_of_order (int num, struct expr_res *args)
{
  struct expr_res t;
  t.v = 0 ;
  t.width = 0;
  if (num !=2 ){
    fprintf(logfile,"[ERROR] wrong number of arguments in channel_check\n");
    return t;
  }
  for (int i = 0; i < check_data_number[args[0].v]; i++){
    if (check_data_used[args[0].v][i] == 0) {
      if (check_data_buffer[args[0].v][i] == args[1].v){
        fprintf(logfile,"[SUCCESS] got %d = %d on check %d - %d\n",check_data_buffer[args[0].v],args[1].v,args[0].v,i); fflush(logfile);
        t.v = 1;
        check_data_used[args[0].v][i] = 1;
        i = check_data_number[args[0].v];
        break;
      }
    }
  }
  if (t.v == 0){
    check_errors++;
    fprintf(logfile,"[FAILURE] could not find %d on check %d; Error count: %d\n",check_data_buffer[args[0].v],args[1].v,args[0].v,check_errors); fflush(logfile);
  }
  t.width = 1;
  return t; 
}

/**
* source_next looks if there is an other word availible to be send in the current simulation step
* it loads that work into the buffer.
* if a new simulation step is loaded the file is read from the beginning again.
* it requires 2 int:
* id: the id of the source
* simstep: the simulation step the next test to be loaded from
* it returns 1 if there is a source word availible, 0 if not or an error occured
*/
struct expr_res source_next (int num, struct expr_res *args)
{
  struct expr_res t;
  t.v = 0 ;
  t.width = 0;
  if (num !=2 ){
    fprintf(logfile,"[ERROR] wrong number of arguments in channel_source_next\n"); fflush(logfile);
    return t;
  }
  if (!source_file[args[0].v]) { 
    fprintf(logfile,"[ERROR] could not read source %d, file not open or does not exist\n",args[0].v); fflush(logfile);
    return t;
  }
  int step_done = 0;
  unsigned int source_sim_step_file = 0;
  unsigned long int sim_data_file = 0;
  if (source_sim_step[args[0].v] != args[1].v){
    rewind(source_file[args[0].v]);
    source_sim_step[args[0].v] = args[1].v;
  }
  while (!step_done){
    int success = 0;
    success = fscanf(source_file[args[0].v], CSV_FORMAT, &source_sim_step_file, &sim_data_file);
    if (success != 2) {
      if(ferror(source_file[args[0].v])) fprintf(logfile,"read error on source %d\n",args[0].v);
      source_data_buffer[args[0].v] = 0;
      if(verbose) fprintf(logfile,"EOF on source %d\n",args[0].v); fflush(logfile);
      t.v = 0 ;
      t.width = 1;
      return t;
    }
    if (source_sim_step_file == source_sim_step[args[0].v]){
      step_done = 1;
      source_data_buffer[args[0].v]= sim_data_file;
      if(verbose) fprintf(logfile,"read %d on source %d\n",sim_data_file,args[0].v); fflush(logfile);
      t.v = 1;
      t.width = 1;
      return t; 
    }
  }
}

/**
* source get reads the buffer and returns the word that was placed by source_next
* it requires 2 int:
* id: the id of the source
* width: the number of bits the source word is supposed to have
* it returns the next word placed by source_next
*/
struct expr_res source_get (int num, struct expr_res *args)
{
  struct expr_res t;
  t.v = 0 ;
  t.width = 0;
  if (num !=2 ){
    fprintf(logfile,"[ERROR] wrong number of arguments in channel_source_get\n");
    return t;
  }
  t.v = source_data_buffer[args[0].v];
  t.width = args[1].v;
  return t; 
}

/**
* dump to file writes every inforamtion it gets into a csv file.
* the file is created and opend on the first write, to not create a lot of empty files that are not required.
* it requires 3 ints:
* id: the id of the dump file
* simstep: the current simulation step
* word: the data word to be written
* it return 1 on success
*/
struct expr_res dump_to_file (int num, struct expr_res *args)
{
  struct expr_res t;
  t.v = 0 ;
  t.width = 1;
  if (num !=3 ){
    fprintf(logfile,"[ERROR] wrong number of arguments in dump_to_file\n");
    return t;
  }
  if (!dump_file[args[0].v]){
    char filename[255];
    snprintf(filename, 255, DUMP_FILENAME,args[0].v);
    dump_file[args[0].v] = fopen(filename,"w");
  }
  if (dump_file[args[0].v]){
    fprintf(dump_file[args[0].v], CSV_WRITE_FORMAT, args[1].v, args[2].v); fflush(dump_file[args[0].v]);
    t.v = 1;
    return t;
  }
  else{
    fprintf(logfile,"[ERROR] writing failed, file not open for dump %d\n",args[0].v); fflush(logfile);
    t.v = 0;
    return t;
  }
}

/**
* control next hecks if there is a next simulation step to be loaded and if a delay needs to be triggered
* it requires 1 ints:
* ignored: cant have a function call without
* it returns 1 if there is a new step
*/
struct expr_res control_next (int num, struct expr_res *args)
{
  struct expr_res t;
  t.v = 0 ;
  t.width = 1;
  if (num !=1 ){
    fprintf(logfile,"[ERROR] wrong number of arguments in dump_to_file\n");
    return t;
  }
  if (current_sim_step < first_sim_step) {
    current_sim_step = first_sim_step;
    t.v = 1 ;
  }
  else if (current_sim_step >= last_sim_step){
    return t;
  }
  else {
    current_sim_step++;
    t.v = 1 ;
  }
  int step_done = 0;
  unsigned int sim_step_file = 0;
  unsigned long int sim_data_file = 0;
  while (!step_done){
    int success = 0;
    success = fscanf(control_file, CSV_FORMAT, &sim_step_file, &sim_data_file);
    if (success != 2) {
      if(ferror(control_file)) fprintf(logfile,"read error on contol\n");
      if(verbose) fprintf(logfile,"EOF on ctl\n"); fflush(logfile);
      current_sim_wait = 0;
      step_done = 1;
    }
    if (sim_step_file == current_sim_step){
      step_done = 1;
      if(verbose) fprintf(logfile,"wait %d\n",sim_data_file); fflush(logfile);
      current_sim_wait = sim_data_file;
    }
  }
  return t;
}

/**
* control_get returns the current time_step, to advance a step call control_next
* ignores all input
* returns the current simstep
*/
struct expr_res control_get (int num, struct expr_res *args)
{
  struct expr_res t;
  t.v = current_sim_step;
  t.width = 32;
  return t; 
}

/**
* control_get returns the wait time required after the current time_step, to advance a step call control_next
* ignores all input
* returns the current wait time
*/
struct expr_res control_wait (int num, struct expr_res *args)
{
  struct expr_res t;
  t.v = current_sim_wait;
  t.width = 32;
  return t; 
}
