//      // verilator_coverage annotation
        //
        //----------------------------------------------------------------------
        // Copyright 2007-2009 Cadence Design Systems, Inc.
        // Copyright 2022 Marvell International Ltd.
        // Copyright 2007-2024 Mentor Graphics Corporation
        // Copyright 2024 Microsoft
        // Copyright 2022-2026 NVIDIA Corporation
        //   All Rights Reserved Worldwide
        //
        //   Licensed under the Apache License, Version 2.0 (the
        //   "License"); you may not use this file except in
        //   compliance with the License.  You may obtain a copy of
        //   the License at
        //
        //       http://www.apache.org/licenses/LICENSE-2.0
        //
        //   Unless required by applicable law or agreed to in
        //   writing, software distributed under the License is
        //   distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
        //   CONDITIONS OF ANY KIND, either express or implied.  See
        //   the License for the specific language governing
        //   permissions and limitations under the License.
        //----------------------------------------------------------------------
        
        //----------------------------------------------------------------------
        // Git details (see DEVELOPMENT.md):
        //
        // $File:     src/base/uvm_phase_hopper.svh $
        // $Rev:      2026-08-10 12:49:20 -0700 $
        // $Hash:     6b8f3b5a4142eb222fd01ec0f2faeb1b3f825924 $
        //
        //----------------------------------------------------------------------
        
        
        
        // Class: uvm_phase_hopper
        //
        // The UVM phase hopper is responsible for the execution of the UVM phases
        // during a test.
        //
        // The UVM Library is responsible for calling ~run_phases~ on the
        // phase hopper after transitioning the state of the UVM core to 
        // UVM_CORE_RUNNING.  The core shall stay in the RUNNING state until
        // the run_phases task completes, at which point it shall transition
        // to the UVM_CORE_POST_RUN state.
        //
        // Phases are added to the hopper via the ~try_set~ method,
        // and are retrieved using the ~try_get~,~get~,~try_peek~, and ~peek~ methods.
        // After retrieving a new phase, the ~run_phases~ task is responsible
        // for transitioning the phase's state through the appropriate path
        // (see <uvm_phase_state>).
        //
        //
        // @uvm-contrib For potential contribution to the 1800.2 standard
        class uvm_phase_hopper extends uvm_object;
        
%000000   `uvm_object_utils(uvm_phase_hopper)
        
          // Function: new
          // Creates a new uvm_phase_hopper instance with ~name~.
          //
          extern function new(string name="uvm_phase_hopper");
        
          // Group: Singleton Accessors
          
          // Function: get_global_hopper
          // Returns the global phase hopper.
          //
          // This method is provided as a wrapper function to conveniently retrieve the
          // phase hopper via the <uvm_coreservice_t::get_phase_hopper> method.
          extern static function uvm_phase_hopper get_global_hopper();
        
          // Group: Queue API
          
          // Function: try_put
          // Attempts to add a new phase to the hopper.
          //
          // If the phase is successfully added to the internal queue, then
          // <raise_objection> is called for ~phase~, and '1' is returned.
          // If the phase can not be added to the internal queue, then no 
          // objection is raised and '0' is returned.
          //
          // NOTE - By default the internal queue has no maximum depth, and
          // as such this method shall always succeed.
          extern virtual function bit try_put(uvm_phase phase);
        
          // Task: get
          // Retrieves the next phase from the hopper.
          //
          // The ~get~ method retrieves the next phase from the hopper, that is, removes one 
          // phase from the internal queue.  If the internal queue is empty, then the current
          // process blocks until a phase is placed in the hopper.
          //
          extern protected virtual task get(output uvm_phase phase);
        
          // Task: try_get
          // Attempts to retrieve the next phase from the hopper.
          //
          // The ~try_get~ method attempts to retrieve the next phase from the hopper.
          // If no phases are available, then the method returns 0; otherwise returns
          // 1.
          extern protected virtual function bit try_get(inout uvm_phase phase);
        
          // Task: peek
          // Copies a phase from the hopper.
          //
          // The ~peek~ method copies a phase from the internal queue without removing it.
          // If the internal queue is empty, then the current process blocks until a phase
          // is placed in the hopper.
          extern protected virtual task peek(output uvm_phase phase);
        
          // Task: try_peek
          // Attempts to copy a phase from the hopper.
          //
          // The ~try_peek~ method attempts to copy a phase from the internal queue without
          // removing it.  If the internal queue is empty, then the method returns 0; otherwise
          // return 1.
          extern protected virtual function bit try_peek(inout uvm_phase phase);
        
          // Group: Active Phase Objection
        
          // Function: get_objection
          // Retrieves the Active Phase Objection.
          //
          // The Active Phase Objection is used to track phases being processed by the hopper, ie. phases
          // that have been added via a call to <try_put>, but have not yet completed processing 
          // via <process_phase>.
          //
          extern protected virtual function uvm_objection get_objection();
        
          // Function: raise_objection
          // This is a pass through to <uvm_objection::raise_objection> on the
          // objection returned by <get_objection>.
          extern protected virtual function void raise_objection(uvm_object obj,
                                                                 string description = "",
                                                                 int count=1);
        
          // Function: drop_objection
          // This is a pass through to <uvm_objection::drop_objection> on the
          // objection returned by <get_objection>.
          extern protected virtual function void drop_objection(uvm_object obj,
                                                                string description = "",
                                                                int count=1);
        
          // Function: get_objection_count
          // This is a pass through to <uvm_objection::get_objection_count> on the
          // objection returned by <get_objection>.
          extern virtual function int get_objection_count( uvm_object obj = null );
        
          // Function: get_objection_total
          // This is a pass through to <uvm_objection::get_objection_total> on the
          // objection returned by <get_objection>.
          extern virtual function int get_objection_total( uvm_object obj = null );
        
          // Function: wait_for_objection
          // This is a pass through to <uvm_objection::wait_for> on the objection
          // returned by <get_objection>.
          extern virtual task wait_for_objection( uvm_objection_event objt_event,
                                                  uvm_object obj = null );
        
          
          // Group: Phase Graph Execution
        
          // Task: run_phases
          // Runs all phases associated with a test.
          //
          // The default implementation causes the following steps to occur
          // in order:
          // * <try_put> is passed <uvm_domain::get_common_domain>
          // * A process is forked in a non-blocking fashion.  The forked
          //   process runs a forever loop that calls <get>.  When ~get~
          //   returns, an additional process is forked in a non-blocking 
          //   fashion that performs the following steps in order:
          //   * <process_phase> is called with the return value of ~get~.
          //   * <drop_objection> is passed the return value of ~get~.
          // * The task is blocked, waiting on `wait_for_objection(UVM_ALL_DROPPED)`.
          //
          // Note that the UVM core state shall transition to UVM_CORE_POST_RUN
          // when ~run_phases~ returns.
          extern virtual task run_phases();
        
          // Task: schedule_phase
          // Performs actions associated with transitioning phase state to the UVM_PHASE_SCHEDULED state.
          //
          // If ~from_phase~ is not null, then phase tracing messages will include the name of the phase 
          // that scheduled ~phase~.
          extern protected virtual task schedule_phase(uvm_phase phase, uvm_phase from_phase = null);
        
          // Task: process_phase
          // Processes a phase.
          //
          // The process_phase task transitions a phase from the SCHEDULED
          // to the DONE state.  
          //
          // It calls the following tasks in order:
          // - sync_phase
          // - start_phase
          // - execute_phase
          // - end_phase
          // - cleanup_phase
          // - finish_phase
          // 
          extern protected virtual task process_phase(uvm_phase phase);
        
          // Task: Transitions
          // Performs actions associated with transitioning phase state to the UVM_PHASE_SYNCING state.
          extern protected virtual task sync_phase(uvm_phase phase);
        
          // Task: start_phase
          // Performs actions associated with transitioning phase state to the UVM_PHASE_STARTED state.
          extern protected virtual task start_phase(uvm_phase phase);
        
          // Task: execute_phase
          // Performs actions associated with transitioning phase state to the UVM_PHASE_EXECUTING state.
          extern protected virtual task execute_phase(uvm_phase phase);
        
          // Task: end_phase
          // Performs actions associated with transitioning phase state to the UVM_PHASE_ENDED state.
          extern protected virtual task end_phase(uvm_phase phase);
        
          // Task: cleanup_phase
          // Performs actions associated with transitioning phase state to the UVM_PHASE_CLEANUP or UVM_PHASE_JUMPING state.
          extern protected virtual task cleanup_phase(uvm_phase phase);
        
          // Task: finish_phase
          // Performs actions associated with transitioning phase state to the UVM_PHASE_DONE state.
          extern protected virtual task finish_phase(uvm_phase phase);
        
          // Task: wait_for_waiters
          // Delays execution to allow waiters on phase state changes to react.
          //
          // By default, <wait_for_waiters> shall pause for a single delta cycle.
          extern protected virtual task wait_for_waiters(uvm_phase phase, uvm_phase_state prev_state);
          
        
          /// Group: Phase Component Traversal
          
          // Function: traverse_on
          // Calls ~traverse~ on ~imp~, passing in ~comp~, ~node~, and ~state~.
          //
          // The ~traverse_on~ function is a hook that allows the phase hopper
          // to witness, and potentially change how a phase traverses the
          // component hierarchy.
          //
          // By default, the ~traverse_on~ method calls <uvm_phase::traverse>
          // for ~imp~ on ~comp~, which will then in turn call ~traverse_on~ for all
          // of ~imp~ on all of ~comp~'s children.
          //
          // Depending on the traversal policy of ~imp~, the phase may be
          // executed on ~comp~ before or after ~traverse_on~ is called for
          // ~comp~'s children.
          //
          // If ~comp~ is null, then the default implementation shall pass
          // <uvm_root::get> to the traverse method.
          extern virtual function void traverse_on(uvm_phase imp,
                                                   uvm_component comp,
                                                   uvm_phase node,
                                                   uvm_phase_state state);
        
          // Function: execute_on
          // Calls ~execute~ on ~imp~, passing in ~comp~, and ~node~.
          //
          // Similar the ~traverse_on~, the ~execute_on~ function is a hook
          // that allows the phase hopper to witness, and potentially change
          // how a phase executes on a component.
          //
          // By default, the ~execute_on~ method calls <uvm_phase::execute>
          // for ~imp~ on ~comp~.
          extern virtual function void execute_on(uvm_phase imp,
                                                  uvm_component comp,
                                                  uvm_phase node);
        
          // Function: set_phase_state
          // Sets the state of the specified phase.
          //
          // This method sets the state of ~phase~ to ~state~.
          //
          // @uvm-contrib For potential contribution to 1800.2
          extern virtual function void set_phase_state(uvm_phase phase, uvm_phase_state state);
        
          /// Implementation Artifacts
        
          local uvm_phase m_queue[$]; // Internal storage
          local uvm_objection m_objection; // Tracks when all phases are complete
          
        endclass // uvm_phase_hopper
        
        /// Implementation
        
~000018 function uvm_phase_hopper::new(string name = "uvm_phase_hopper");
 000018   super.new(name);
 000018   m_objection = new("phase_hopper_objection");
        endfunction : new
        
 280854 function uvm_phase_hopper uvm_phase_hopper::get_global_hopper();
 280854   uvm_coreservice_t cs;
 280854   cs = uvm_coreservice_t::get();
 280854   return cs.get_phase_hopper();
        endfunction : get_global_hopper
        
 000486 function bit uvm_phase_hopper::try_put(uvm_phase phase);
 000486   raise_objection(phase, "phase scheduled"); // drop in run_phases
 000486   m_queue.push_back(phase);
 000486   return 1;
        endfunction : try_put
        
 000486 task uvm_phase_hopper::get(output uvm_phase phase);
 000486   wait (m_queue.size() != 0);
 000486   phase = m_queue.pop_front();
        endtask : get
        
%000000 function bit uvm_phase_hopper::try_get(inout uvm_phase phase);
%000000   if (m_queue.size() > 0) begin
%000000     phase = m_queue.pop_front();
%000000     return 1;
          end
%000000   else begin
%000000     return 0;
          end
        endfunction : try_get
        
%000000 task uvm_phase_hopper::peek(output uvm_phase phase);
%000000   wait (m_queue.size() != 0);
%000000   phase = m_queue[0];
        endtask : peek
        
%000000 function bit uvm_phase_hopper::try_peek(inout uvm_phase phase);
%000000   if (m_queue.size() > 0) begin
%000000     phase = m_queue[0];
%000000     return 1;
          end
%000000   else begin
%000000     return 0;
          end
        endfunction : try_peek
        
 000990 function uvm_objection uvm_phase_hopper::get_objection();
~000990   if (m_objection == null) begin
            
%000000     m_objection = new("phase_hopper_objection");
          end
        
 000990   return m_objection;
        endfunction : get_objection
        
 000486 function void uvm_phase_hopper::raise_objection(uvm_object obj,
                                                        string description = "",
 000486                                                 int count=1);
 000486   uvm_objection objection;
 000486   objection = get_objection();
 000486   objection.raise_objection(obj, description, count);
        endfunction : raise_objection
        
 000486 function void uvm_phase_hopper::drop_objection(uvm_object obj,
                                                       string description = "",
 000486                                                int count=1);
 000486   uvm_objection objection;
 000486   objection = get_objection();
 000486   objection.drop_objection(obj, description, count);
        endfunction : drop_objection
        
%000000 function int uvm_phase_hopper::get_objection_count(uvm_object obj = null);
%000000   uvm_objection objection;
%000000   objection = get_objection();
%000000   return objection.get_objection_count(obj);
        endfunction : get_objection_count
        
%000000 function int uvm_phase_hopper::get_objection_total(uvm_object obj = null);
%000000   uvm_objection objection;
%000000   objection = get_objection();
%000000   return objection.get_objection_total(obj);
        endfunction : get_objection_total
        
 000018 task uvm_phase_hopper::wait_for_objection( uvm_objection_event objt_event,
 000018                                            uvm_object obj = null );
 000018   uvm_objection objection;
 000018   objection = get_objection();
 000018   objection.wait_for(objt_event, obj);
        endtask : wait_for_objection
        
 000018 task uvm_phase_hopper::run_phases();
          // initiate by starting first phase in common domain
 000018   uvm_phase ph;
 000018   ph = uvm_domain::get_common_domain();
 000018   schedule_phase(ph);
        
 000018   fork
 000018     begin
 000486       forever begin
 000486         this.get(ph);
 000486         fork
 000486           automatic uvm_phase phase = ph;
 000486           begin
 000486             this.process_phase(phase);
 000486             drop_objection(phase, "phase done"); // raised in try_put
                  end
                join_none
              end
            end
          join_none
        
 000018   wait_for_objection(UVM_ALL_DROPPED);
        endtask : run_phases
        
        // Inside the schedule stage 
 000504 task uvm_phase_hopper::schedule_phase(uvm_phase phase, uvm_phase from_phase = null);
 000504   uvm_phase_state prev_state;
 000504   prev_state = phase.get_state();
 000486   if(prev_state < UVM_PHASE_SCHEDULED) begin
 000486     this.set_phase_state(phase, UVM_PHASE_SCHEDULED);
 000486     wait_for_waiters(phase, prev_state);
 000486     void'(this.try_put(phase));
~000486     `UVM_PH_TRACE("PH/TRC/SCHEDULED",{"Scheduled from ", (from_phase != null) ? {"phase ",from_phase.get_full_name()}:"run_test"},phase,UVM_LOW)
          end
        endtask : schedule_phase
          
        // Inside the sync stage 
 000486 task uvm_phase_hopper::sync_phase(uvm_phase phase);
 000486   uvm_phase::edges_t edges;
 000486   uvm_phase_state prev_state;
          // Scheduled phases must wait for all predecessors to complete
 000486   phase.get_predecessors(edges);
 000486   foreach(edges[p]) begin
            
 000486     p.wait_for_state(UVM_PHASE_DONE);
          end
        
        
 000486   prev_state = phase.get_state();
 000486   this.set_phase_state(phase, UVM_PHASE_SYNCING);
 000486   wait_for_waiters(phase, prev_state);
        
 000486   phase.get_sync_relationships(edges);
 000486   foreach (edges[s]) begin
            
 000486     s.wait_for_state(UVM_PHASE_SYNCING, UVM_GTE);
          end
        
        endtask : sync_phase
        
        // Inside the started stage
 000486 task uvm_phase_hopper::start_phase(uvm_phase phase);
 000486   uvm_phase_state prev_state;
~000486   `UVM_PH_TRACE("PH/TRC/STRT","Starting phase",phase,UVM_LOW)
        
 000486   prev_state = phase.get_state();
 000486   this.set_phase_state(phase, UVM_PHASE_STARTED);
        
          // Only nodes traverse_on
 000378   if (phase.get_phase_type() == UVM_PHASE_NODE) begin
 000378     uvm_phase imp;
 000378     imp = phase.get_imp();
 000378     traverse_on(imp, null, phase, UVM_PHASE_STARTED);
          end
              
 000486   wait_for_waiters(phase, prev_state);
        endtask : start_phase
        
        // Inside the executing stage
 000486 task uvm_phase_hopper::execute_phase(uvm_phase phase);
 000486   uvm_phase_state prev_state;
 000486   prev_state = phase.get_state();
 000486   this.set_phase_state(phase, UVM_PHASE_EXECUTING);
        
          // Only nodes traverse_on
~000378   if (phase.get_phase_type() != UVM_PHASE_NODE) begin
%000000     wait_for_waiters(phase, prev_state);
%000000     return;
          end
 000378   else begin
 000378     uvm_root top;
 000378     uvm_phase imp;
 000378     uvm_task_phase task_phase;
 000378     top = uvm_root::get();
 000378     imp = phase.get_imp();
 000234     if (!$cast(task_phase, imp)) begin
              // Non-Task (ie. Function) phase
 000144       wait_for_waiters(phase, prev_state);
 000144       traverse_on(imp, null, phase, UVM_PHASE_EXECUTING);
            end
 000234     else begin
              // Task phases
 000234       fork : master_phase_process
 000234         begin
 000234           phase.m_phase_proc = process::self();
 000234           traverse_on(task_phase, null, phase, UVM_PHASE_EXECUTING);
                  // This shouldn't be strictly necessary, as kill
                  // should kill subprocesses even if the process
                  // has ended, but leaving it in for compatibility.
 000234           wait(0);
                end // else: !if(!$cast(task_phase, imp))
              join_none
        
              // Give sequences, etc. a chance to object
 000234       uvm_wait_for_nba_region();
        
              // Wait for one of three criterion to end-of-phase:
              // - JUMP (Premature end)
              // - ALL DROPPED
              // - TIMEOUT
 000234       fork
 000234         begin // guard
                  
 000234           fork
 000234             begin // JUMP (Premature end)
 000234               wait (phase.m_premature_end);
%000000               `UVM_PH_TRACE("PH/TRC/EXE/JUMP","PHASE EXIT ON JUMP REQUEST",phase,UVM_DEBUG)
                    end // JUMP (Premature end)
                    
 000234             begin // ALL DROPPED
 000234               int unsigned ready_to_end_count;
 000234               bit do_ready_to_end; // bit used for ready_to_end iterations
 000234               uvm_objection phase_done;
 000234               phase_done = phase.get_objection();
                      // OVM semantic: don't end until objection raised or stop request
 000216               if (phase_done.get_objection_total(top) ||
 000018               phase.m_use_ovm_run_semantic && imp.get_name() == "run") begin
~000018                 if (!phase_done.m_top_all_dropped) begin
                          
 000018                   phase_done.wait_for(UVM_ALL_DROPPED, top);
                        end
        
~000018                 `UVM_PH_TRACE("PH/TRC/EXE/ALLDROP","PHASE EXIT ALL_DROPPED",phase,UVM_DEBUG)
                      end
 000216               else begin
~000216                 `UVM_PH_TRACE("PH/TRC/SKIP","No objections raised, skipping phase",phase,UVM_LOW)
                      end
                      
 000234               phase.wait_for_self_and_siblings_to_drop() ;
 000234               do_ready_to_end = 1;
                      
                      //--------------
                      // READY_TO_END:
                      //--------------
                      
 000234               while (do_ready_to_end) begin
 000234                 uvm_wait_for_nba_region(); // Let all siblings see no objections before traverse_on might raise another
~000234                 `UVM_PH_TRACE("PH_READY_TO_END","PHASE READY TO END",phase,UVM_DEBUG)
 000234                 ready_to_end_count++;
~000234                 `UVM_PH_TRACE("PH_READY_TO_END_CB","CALLING READY_TO_END CB",phase,UVM_HIGH)
 000234                 this.set_phase_state(phase, UVM_PHASE_READY_TO_END);
~000234                 if (imp != null) begin
                          
 000234                   traverse_on(imp, null, phase, UVM_PHASE_READY_TO_END);
                        end
        
                        
 000234                 uvm_wait_for_nba_region(); // Give traverse_on targets a chance to object 
                        
 000234                 phase.wait_for_self_and_siblings_to_drop();
 000234                 do_ready_to_end = (phase.get_state() == UVM_PHASE_EXECUTING) && 
                        (ready_to_end_count < phase.get_max_ready_to_end_iterations()) ; //when we don't wait in task above, we drop out of while loop
                      end
                    end // ALL DROPPED
                    
 000234             begin // TIMEOUT
%000000               if (phase.get_name() == "run") begin
%000000                 string delay_type;
%000000                 time   delay_time;
%000000                 uvm_object objectors[$];
~000018                 if (top.phase_timeout == 0) begin
                          
%000000                   wait(top.phase_timeout != 0);
                        end
        
                        `UVM_PH_TRACE("PH/TRC/TO_WAIT", 
                        $sformatf("STARTING PHASE TIMEOUT WATCHDOG (timeout == %t)", top.phase_timeout), 
~000018                 phase, UVM_HIGH)
%000000                 `uvm_delay(top.phase_timeout)
%000000                 if ($time == `UVM_DEFAULT_TIMEOUT) begin
%000000                   delay_type = "Default";
%000000                   delay_time = `UVM_DEFAULT_TIMEOUT;
                        end
%000000                 else begin
%000000                   delay_type = "Explicit";
%000000                   delay_time = top.phase_timeout;
                        end
                        
%000000                 `UVM_PH_TRACE("PH/TRC/TIMEOUT", "PHASE TIMEOUT WATCHDOG EXPIRED", phase, UVM_LOW)
%000000                 m_objection.get_objectors(objectors);
%000000                 foreach (objectors[i]) begin
%000000                   uvm_phase p;
%000000                   if ($cast(p, objectors[i])) begin
%000000                     uvm_objection p_done;
%000000                     p_done = p.get_objection();
%000000                     if ((p_done != null) && (p_done.get_objection_total() > 0)) begin
                              `UVM_PH_TRACE("PH/TRC/TIMEOUT/OBJCTN", 
                              $sformatf("Phase '%s' has outstanding objections:\n%s", p.get_full_name(), p_done.convert2string()),
                              phase,
%000000                       UVM_LOW)
                            end
                          end // $cast
                        end // foreach (objectors[i])
                        
                        `uvm_fatal("PH_TIMEOUT",
                        $sformatf("%s timeout of %0t hit, indicating a probable testbench issue",
                        delay_type, delay_time)
%000000                 )
                        
                      end // if (phase.get_name() == "run")
%000000               else begin
%000000                 wait (0); // never unblock for non-run phase
                      end
                    end // TIMEOUT
                    
                  join_any
 000234           disable fork;
                  
                end // fork begin
                
              join // guard
              
            end // else: !if(!$cast(task_phase, imp))
            
          end // else: !if(phase.get_type() != UVM_PHASE_NODE)
          
        endtask : execute_phase
        
 000486 task uvm_phase_hopper::end_phase(uvm_phase phase);
 000378   if (phase.get_phase_type() == UVM_PHASE_NODE) begin
 000378     uvm_phase_state prev_state;
 000378     uvm_phase imp;
 000378     prev_state = phase.get_state();
 000378     imp = phase.get_imp();
        
~000378     if(phase.m_premature_end) begin
%000000       uvm_phase jump_phase;
%000000       jump_phase = phase.get_jump_target();
%000000       if(jump_phase != null) begin 
                `uvm_info("PH_JUMP",
                $sformatf("phase %s (schedule %s, domain %s) is jumping to phase %s",
                phase.get_name(), 
                phase.get_schedule_name(), 
                phase.get_domain_name(), 
                jump_phase.get_name()),
%000000         UVM_MEDIUM)
              end
%000000       else begin
                `uvm_info("PH_JUMP",
                $sformatf("phase %s (schedule %s, domain %s) is ending prematurely",
                phase.get_name(), 
                phase.get_schedule_name(), 
                phase.get_domain_name()),
%000000         UVM_MEDIUM)
              end
          
%000000       wait_for_waiters(phase, prev_state); // LET ANY WAITERS ON READY_TO_END TO WAKE UP
%000000       `UVM_PH_TRACE("PH_END","ENDING PHASE PREMATURELY",phase,UVM_HIGH)
              
            end
 000378     else begin
              // WAIT FOR PREDECESSORS:  // WAIT FOR PREDECESSORS:
              // function phases only
 000378       uvm_task_phase task_phase;
 000234       if (!$cast(task_phase, phase.get_imp())) begin
                
 000144         phase.m_wait_for_pred();
              end
        
            end
          
            //-------
            // ENDED:
            //-------
            // execute 'phase_ended' callbacks
~000378     `UVM_PH_TRACE("PH_END","ENDING PHASE",phase,UVM_HIGH)
 000378     this.set_phase_state(phase, UVM_PHASE_ENDED);
~000378     if (imp != null) begin
              
 000378       traverse_on(imp, null, phase, UVM_PHASE_ENDED);
            end
        
 000378     wait_for_waiters(phase, prev_state);
          end // if (phase_type == UVM_PHASE_NODE)
         
        endtask : end_phase
        
 000486 task uvm_phase_hopper::cleanup_phase(uvm_phase phase);
        
          // Only nodes need cleanup/jumping
 000378   if (phase.get_phase_type() == UVM_PHASE_NODE) begin
 000378     uvm_objection phase_done;
 000378     uvm_phase_state prev_state;
 000378     prev_state = phase.get_state();
            // kill this phase's threads
~000378     if(phase.m_premature_end) begin
        
%000000       this.set_phase_state(phase, UVM_PHASE_JUMPING);
            end
        
 000378     else begin
        
 000378       this.set_phase_state(phase, UVM_PHASE_CLEANUP);
            end
        
        
 000234     if (phase.m_phase_proc != null) begin
 000234       phase.m_phase_proc.kill();
 000234       phase.m_phase_proc = null;
            end
 000378     wait_for_waiters(phase, prev_state);
 000378     phase_done = phase.get_objection();
 000234     if (phase_done != null) begin
              
 000234       phase_done.clear();
            end
        
          end // if (phase_type == UVM_PHASE_NODE)
          
        endtask : cleanup_phase
          
 000486 task uvm_phase_hopper::finish_phase(uvm_phase phase);
 000486   uvm_objection phase_done;
 000486   uvm_phase jump_phase;
 000486   uvm_phase_state prev_state;
        
 000486   phase_done = phase.get_objection();
 000486   jump_phase = phase.get_jump_target();
 000486   prev_state = phase.get_state();
          
          // If jump_to() was called then we need to clear all the successor
          // phases which may still be running and then initiate the new
          // phase.  If we are doing a forward jump then we want to set the
          // state of this phase's successors to UVM_PHASE_DONE.  This
          // will let us pretend that all the phases between here and there
          // were executed and completed.  Thus any dependencies will be
          // satisfied preventing deadlocks.
        
~000486   if(jump_phase != null) begin
%000000     if(phase.is_jumping_forward()) begin
%000000       phase.clear_successors(UVM_PHASE_DONE,jump_phase);
            end
%000000     jump_phase.clear_successors();
%000000     phase.set_jump_phase(null);
          end
 000486   else begin
        
~000486     `UVM_PH_TRACE("PH/TRC/DONE","Completed phase",phase,UVM_LOW)
 000486     this.set_phase_state(phase, UVM_PHASE_DONE);
 000486     phase.m_phase_proc = null;
          end
        
 000486   wait_for_waiters(phase, prev_state);
 000486   begin
 000252     if (phase_done != null) begin
              
 000234       phase_done.clear();
            end
        
          end
        
          //-----------
          // SCHEDULE:
          //-----------
~000486   if(jump_phase != null) begin
%000000     schedule_phase(jump_phase, phase);
          end
 000486   else begin
 000486     uvm_phase::edges_t edges;
 000486     uvm_phase succ_q[$];
 000486     phase.get_successors(edges);
 000468     if (edges.size() != 0) begin
              // Need to sort the list
 000468       uvm_phase succ;
        
 000486       foreach (edges[succ]) begin
                
 000486         succ_q.push_back(succ);
              end
        
 000468       succ_q.sort with ( item.get_full_name() );
        
              // execute all the successors
~000486       foreach (succ_q[i]) begin
 000486         schedule_phase(succ_q[i], phase);
              end
            end
          end
          
        endtask : finish_phase
        
          
 000486 task uvm_phase_hopper::process_phase(uvm_phase phase);
        
 000486     sync_phase(phase);
 000486     start_phase(phase);
 000486     execute_phase(phase);
 000486     end_phase(phase);
 000486     cleanup_phase(phase);
 000486     finish_phase(phase);
            
        endtask : process_phase
        
 002952 task uvm_phase_hopper::wait_for_waiters(uvm_phase phase, uvm_phase_state prev_state);
 002952   #0;
        endtask : wait_for_waiters
        
 280836 function void uvm_phase_hopper::traverse_on(uvm_phase imp,
                                                    uvm_component comp,
                                                    uvm_phase node,
                                                    uvm_phase_state state);
 279468   if (comp == null) begin
            
 001368     comp = uvm_root::get();
          end
        
 280836   imp.traverse(comp, node, state);
        endfunction : traverse_on
        
 078624 function void uvm_phase_hopper::execute_on(uvm_phase imp,
                                                   uvm_component comp,
                                                   uvm_phase node);
 078624   imp.execute(comp, node);
        endfunction : execute_on
        
 003420 function void uvm_phase_hopper::set_phase_state(uvm_phase phase, uvm_phase_state state);
 003420   phase.set_state(state);
        endfunction : set_phase_state
        
        
