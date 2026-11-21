//      // verilator_coverage annotation
        //
        //----------------------------------------------------------------------
        // Copyright 2011 AMD
        // Copyright 2007-2018 Cadence Design Systems, Inc.
        // Copyright 2007-2011 Mentor Graphics Corporation
        // Copyright 2013-2024 NVIDIA Corporation
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
        // $File:     src/base/uvm_task_phase.svh $
        // $Rev:      2026-08-10 12:49:20 -0700 $
        // $Hash:     6b8f3b5a4142eb222fd01ec0f2faeb1b3f825924 $
        //
        //----------------------------------------------------------------------
        
        
        //------------------------------------------------------------------------------
        //
        // Class -- NODOCS -- uvm_task_phase
        //
        //------------------------------------------------------------------------------
        // Base class for all task phases.
        // It forks a call to <uvm_phase::exec_task()>
        // for each component in the hierarchy.
        //
        // The completion of the task does not imply, nor is it required for, 
        // the end of phase. Once the phase completes, any remaining forked 
        // <uvm_phase::exec_task()> threads are forcibly and immediately killed.
        //
        // By default, the way for a task phase to extend over time is if there is
        // at least one component that raises an objection.  
        //| class my_comp extends uvm_component;
        //|    task main_phase(uvm_phase phase);
        //|       phase.raise_objection(this, "Applying stimulus")
        //|       ...
        //|       phase.drop_objection(this, "Applied enough stimulus")
        //|    endtask
        //| endclass
        // 
        //   
        // There is however one scenario wherein time advances within a task-based phase
        // without any objections to the phase being raised. If two (or more) phases 
        // share a common successor, such as the <uvm_run_phase> and the 
        // <uvm_post_shutdown_phase> sharing the <uvm_extract_phase> as a successor, 
        // then phase advancement is delayed until all predecessors of the common 
        // successor are ready to proceed.  Because of this, it is possible for time to 
        // advance between <uvm_component::phase_started> and <uvm_component::phase_ended>
        // of a task phase without any participants in the phase raising an objection.
        //
        
        // @uvm-ieee 1800.2-2020 auto 9.6.1
        virtual class uvm_task_phase extends uvm_phase;
        
        
        
          // @uvm-ieee 1800.2-2020 auto 9.6.2.1
 000234   function new(string name);
 000234     super.new(name,UVM_PHASE_IMP);
          endfunction
        
        
        
          // @uvm-ieee 1800.2-2020 auto 9.6.2.2
 194688   virtual function void traverse(uvm_component comp,
                                         uvm_phase phase,
                                         uvm_phase_state state);
 194688     phase.m_num_procs_not_yet_returned = 0;
 194688     m_traverse(comp, phase, state);
          endfunction
        
 194688   function void m_traverse(uvm_component comp,
                                   uvm_phase phase,
                                   uvm_phase_state state);
 194688     string name;
 194688     uvm_domain phase_domain =phase.get_domain();
 194688     uvm_domain comp_domain = comp.get_domain();
 194688     uvm_sequencer_base seqr;
 194688     uvm_phase_hopper hopper;
 194688     hopper = uvm_phase_hopper::get_global_hopper();
            
 136656     if (comp.get_first_child(name)) begin
              
 193752       do begin
                
 193752         hopper.traverse_on(this, comp.get_child(name), phase, state);
              end
 193752       while(comp.get_next_child(name));
            end
        
        
~194688     if (m_phase_trace) begin
              `uvm_info("PH_TRACE",$sformatf("topdown-phase phase=%s state=%s comp=%s comp.domain=%s phase.domain=%s",
              phase.get_name(), state.name(), comp.get_full_name(),comp_domain.get_name(),phase_domain.get_name()),
%000000       UVM_DEBUG)
            end
        
~194688     if (phase_domain == uvm_domain::get_common_domain() ||
 194688         phase_domain == comp_domain) begin
 194688       case (state)
 048672         UVM_PHASE_STARTED: begin
 048672           comp.m_current_phase = phase;
 048672           comp.m_apply_verbosity_settings(phase);
 048672           comp.phase_started(phase);
 046800           if ($cast(seqr, comp)) begin
                    
 001872             seqr.start_phase_sequence(phase);
                  end
        
                end
 048672         UVM_PHASE_EXECUTING: begin
 048672           uvm_phase ph = this; 
~048672           if (comp.m_phase_imps.exists(this)) begin
                    
%000000             ph = comp.m_phase_imps[this];
                  end
        
 048672           hopper.execute_on(ph, comp, phase);
                end
 048672         UVM_PHASE_READY_TO_END: begin
 048672           comp.phase_ready_to_end(phase);
                end
 048672         UVM_PHASE_ENDED: begin
 046800           if ($cast(seqr, comp)) begin
                    
 001872             seqr.stop_phase_sequence(phase);
                  end
        
 048672           comp.phase_ended(phase);
 048672           comp.m_current_phase = null;
                end
%000000         default: begin
%000000           `uvm_fatal("PH_BADEXEC","task phase traverse internal error")
                end
              endcase
            end
        
          endfunction
        
        
        
          // @uvm-ieee 1800.2-2020 auto 9.6.2.3
 048672   virtual function void execute(uvm_component comp,
                                                  uvm_phase phase);
        
 048672     fork
 048672       begin
 048672         process proc;
        
                // reseed this process for random stability
 048672         proc = process::self();
 048672         proc.srandom(uvm_create_random_seed(phase.get_type_name(), comp.get_full_name()));
        
 048672         phase.m_num_procs_not_yet_returned++;
        
 048672         exec_task(comp,phase);
        
 048672         phase.m_num_procs_not_yet_returned--;
        
              end
            join_none
        
          endfunction
        endclass
        
