//      // verilator_coverage annotation
        //----------------------------------------------------------------------
        // Copyright 2023-2024 NVIDIA Corporation
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
        // $File:     src/base/uvm_process_guard_base.svh $
        // $Rev:      2026-08-10 12:49:20 -0700 $
        // $Hash:     6b8f3b5a4142eb222fd01ec0f2faeb1b3f825924 $
        //
        //----------------------------------------------------------------------
        
        // Class: uvm_process_guard_base
        // Non-parameterized base class for <uvm_process_guard#(T)>.
        //
        // @uvm-contrib This API is being considered for potential contribution to 1800.2
        virtual class uvm_process_guard_base extends uvm_object;
        
          // Function: new
          // Constructor.
          //
          // The constructor initializes a new process guard with ~name~ and
          // sets the guarded process to `process::self()`.  
          //
          // @uvm-contrib This API is being considered for potential contribution to 1800.2
          extern function new(string name);
        
          // Function: clear
          // Clears the currently guarded process if it has not yet terminated.
          //
          // If the guarded process has not been terminated, then clear shall
          // return it; otherwise returns `null`.
          //
          // @uvm-contrib This API is being considered for potential contribution to 1800.2
          extern function process clear();
          
          // Group: Process Guard Status
        
          // Function: get_process
          // Returns the currently guarded process, or ~null~ if the guard has been
          // cleared.
          //
          // @uvm-contrib This API is being considered for potential contribution to 1800.2
          extern function process get_process();
        
          // Function: is_terminated
          // Returns true if the guarded process terminated prior to being cleared;
          // otherwise, returns false.
          //
          // @uvm-contrib This API is being considered for potential contribution to 1800.2
          extern function bit is_terminated();
        
          // Group: Hook
          
          // Function: do_trigger
          // Hook called when the guarded process transitions to either the `FINISHED`
          // or `KILLED` state.
          //
          // @uvm-contrib This API is being considered for potential contribution to 1800.2
%000000   pure virtual function void do_trigger();
        
          /// Implementation
        
          extern static function void m_init_process_guards();
          extern static function void m_process_guard(uvm_process_guard_base guard);
        
          protected static uvm_process_guard_base m_pending_guards[$];
        
          protected process m_target_process; // Process being watched
          protected process m_guard_process; // Process watching m_target_process
        
        endclass : uvm_process_guard_base
        
        /// uvm_process_guard_base implementations
        
 000288 function uvm_process_guard_base::new(string name);
 000288   super.new(name);
 000288   m_target_process = process::self();
        endfunction : new
        
%000000 function process uvm_process_guard_base::get_process();
%000000   return this.m_target_process;
        endfunction : get_process
        
 000288 function bit uvm_process_guard_base::is_terminated();
 000288   return ((m_target_process != null) && 
                  ((m_target_process.status() == process::FINISHED) ||
                   (m_target_process.status() == process::KILLED))
                  );
        endfunction : is_terminated
        
 000288 function process uvm_process_guard_base::clear();
~000288   if (this.m_guard_process != null) begin
 000288     this.m_guard_process.kill();
          end
        
~000288   if (is_terminated()) begin
%000000     return null;
          end
        
 000288   clear = this.m_target_process;
 000288   this.m_target_process = null;
        
        endfunction : clear
        
        
        // Run at time 0 by uvm_root, forks off an always running
        // process that waits for new processes to appear and
        // calls m_process_guard.
 000018 function void uvm_process_guard_base::m_init_process_guards();
 000018   fork
 000018     begin
 000288       forever
 000288         begin
 000288           uvm_process_guard_base next_guard;
 000288           wait(m_pending_guards.size() != 0);
 000288           next_guard = m_pending_guards.pop_front();
                  // Don't process if it was already cleared
~000288           if (next_guard.m_target_process != null) begin
 000288             uvm_process_guard_base::m_process_guard(next_guard);
                  end
                end
            end
          join_none
        endfunction : m_init_process_guards
        
 000288 function void uvm_process_guard_base::m_process_guard(uvm_process_guard_base guard);
          // Spawn another fork/join_none to monitor this process guard
 000288   fork
 000288     begin
              // Don't continue if guard was already cleared
%000000       if (guard.m_target_process != null) begin
                // Set the watcher process
%000000         guard.m_guard_process = process::self();
                // Wait for it to either be in the killed or 
%000000         guard.m_target_process.await(); // Wait for KILLED or FINISHED
                // Trigger the callback hook
%000000         guard.do_trigger();
              end
            end
          join_none
        endfunction : m_process_guard
        
        
