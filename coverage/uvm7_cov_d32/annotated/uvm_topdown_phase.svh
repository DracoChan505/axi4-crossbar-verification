//      // verilator_coverage annotation
        //
        //----------------------------------------------------------------------
        // Copyright 2011 AMD
        // Copyright 2007-2018 Cadence Design Systems, Inc.
        // Copyright 2007-2011 Mentor Graphics Corporation
        // Copyright 2015-2024 NVIDIA Corporation
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
        // $File:     src/base/uvm_topdown_phase.svh $
        // $Rev:      2026-08-10 12:49:20 -0700 $
        // $Hash:     6b8f3b5a4142eb222fd01ec0f2faeb1b3f825924 $
        //
        //----------------------------------------------------------------------
        
        
        //------------------------------------------------------------------------------
        //
        // Class -- NODOCS -- uvm_topdown_phase
        //
        //------------------------------------------------------------------------------
        // Virtual base class for function phases that operate top-down.
        // The pure virtual function execute() is called for each component.
        //
        // A top-down function phase completes when the <execute()> method
        // has been called and returned on all applicable components
        // in the hierarchy.
        
        // @uvm-ieee 1800.2-2020 auto 9.7.1
        virtual class uvm_topdown_phase extends uvm_phase;
        
        
        
          // @uvm-ieee 1800.2-2020 auto 9.7.2.1
 000036   function new(string name);
 000036     super.new(name,UVM_PHASE_IMP);
          endfunction
        
        
        
          // @uvm-ieee 1800.2-2020 auto 9.7.2.2
 018756   virtual function void traverse(uvm_component comp,
                                         uvm_phase phase,
                                         uvm_phase_state state);
 018756     string name;
 018756     uvm_domain phase_domain = phase.get_domain();
 018756     uvm_domain comp_domain = comp.get_domain();
 018756     uvm_phase_hopper hopper;
 018756     hopper = uvm_phase_hopper::get_global_hopper();
        
~018756     if (m_phase_trace) begin
              `uvm_info("PH_TRACE",$sformatf("topdown-phase phase=%s state=%s comp=%s comp.domain=%s phase.domain=%s",
              phase.get_name(), state.name(), comp.get_full_name(),comp_domain.get_name(),phase_domain.get_name()),
%000000       UVM_DEBUG)
            end
        
~018756     if (phase_domain == uvm_domain::get_common_domain() ||
 018756         phase_domain == comp_domain) begin
 018756       case (state)
 003780         UVM_PHASE_STARTED: begin
 003780           comp.m_current_phase = phase;
 003780           comp.m_apply_verbosity_settings(phase);
 003780           comp.phase_started(phase);
                end
 007488         UVM_PHASE_EXECUTING: begin
~007488           if (!(phase.get_name() == "build" && comp.m_build_done)) begin
 007488             uvm_phase ph = this; 
 007488             comp.m_phasing_active++;
~007488             if (comp.m_phase_imps.exists(this)) begin
                        
%000000               ph = comp.m_phase_imps[this];
                    end
        
 007488             hopper.execute_on(ph, comp, phase);
 007488             comp.m_phasing_active--;
                  end
                end
%000000         UVM_PHASE_READY_TO_END: begin
%000000           comp.phase_ready_to_end(phase);
                end
 007488         UVM_PHASE_ENDED: begin
 007488           comp.phase_ended(phase);
 007488           comp.m_current_phase = null;
                end
%000000         default: begin
%000000           `uvm_fatal("PH_BADEXEC","topdown phase traverse internal error")
                end
                endcase
            end
 013158     if(comp.get_first_child(name)) begin
              
 018648       do begin
                
 018648         hopper.traverse_on(this, comp.get_child(name), phase, state);
              end
 018648       while(comp.get_next_child(name));
            end
        
          endfunction
        
        
        
          // @uvm-ieee 1800.2-2020 auto 9.7.2.3
 007488   virtual function void execute(uvm_component comp,
                                                  uvm_phase phase);
            // reseed this process for random stability
 007488     process proc = process::self();
 007488     proc.srandom(uvm_create_random_seed(phase.get_type_name(), comp.get_full_name()));
        
 007488     comp.m_current_phase = phase;
 007488     exec_func(comp,phase);
          endfunction
        
        endclass
        
