//      // verilator_coverage annotation
        //----------------------------------------------------------------------
        // Copyright 2010-2011 AMD
        // Copyright 2015 Analog Devices, Inc.
        // Copyright 2010-2018 Cadence Design Systems, Inc.
        // Copyright 2017-2018 Cisco Systems, Inc.
        // Copyright 2011-2012 Cypress Semiconductor Corp.
        // Copyright 2017 Intel Corporation
        // Copyright 2021-2022 Marvell International Ltd.
        // Copyright 2010-2022 Mentor Graphics Corporation
        // Copyright 2013-2024 NVIDIA Corporation
        // Copyright 2010-2011 Paradigm Works
        // Copyright 2014 Semifore
        // Copyright 2010-2014 Synopsys, Inc.
        // Copyright 2017-2018 Verific
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
        // $File:     src/base/uvm_resource.svh $
        // $Rev:      2026-08-10 12:49:20 -0700 $
        // $Hash:     6b8f3b5a4142eb222fd01ec0f2faeb1b3f825924 $
        //
        //----------------------------------------------------------------------
        
        
        
        
        
        //----------------------------------------------------------------------
        // Class: uvm_resource #(T)
        // Implementation of uvm_resource#(T) as defined in section C.2.5.1 of
        // 1800.2-2020.
        //----------------------------------------------------------------------
        
        // @uvm-ieee 1800.2-2020 auto C.2.5.1
        class uvm_resource #(type T=int) extends uvm_resource_base;
        
          typedef uvm_resource#(T) this_type;
        
          // singleton handle that represents the type of this resource
 000018   static this_type my_type = get_type();
        
          // Can't be rand since things like rand strings are not legal.
          protected T val;
        
          // Because of uvm_resource#(T)::get_type, we can't use
          // the macros.  We need to do it all manually.
          typedef uvm_object_registry#(this_type) type_id;
%000000   virtual function uvm_object_wrapper get_object_type();
%000000     return type_id::get();
          endfunction : get_object_type
%000000   virtual function uvm_object create (string name="");
%000000     this_type tmp;
%000000     if (name=="") begin
%000000       tmp = new();
            end
        
%000000     else begin
%000000       tmp = new(name);
            end
        
%000000     return tmp;
          endfunction : create
%000000   `uvm_type_name_decl($sformatf("uvm_resource#(%s)", `uvm_typename(T)))
          
          
          // @uvm-ieee 1800.2-2020 auto C.2.5.2
~000306   function new(string name="", string scope="<not provided>"); //scope argument added for compatibility
 000306     super.new(name,scope);
          endfunction
        
%000000   virtual function string m_value_type_name();
%000000     return `uvm_typename(T);
          endfunction : m_value_type_name
                                            
%000000   virtual function string m_value_as_string();
%000000     return $sformatf("%p", val);
          endfunction : m_value_as_string
                                            
          //----------------------
          // Group -- NODOCS -- Type Interface
          //----------------------
          //
          // Resources can be identified by type using a static type handle.
          // The parent class provides the virtual function interface
          // <get_type_handle>.  Here we implement it by returning the static type
          // handle.
        
          // Function -- NODOCS -- get_type
          //
          // Static function that returns the static type handle.  The return
          // type is this_type, which is the type of the parameterized class.
        
 009486   static function this_type get_type();
~009468     if(my_type == null) begin
              
 000018       my_type = new();
            end
        
 009486     return my_type;
          endfunction
        
          // Function -- NODOCS -- get_type_handle
          //
          // Returns the static type handle of this resource in a polymorphic
          // fashion.  The return type of get_type_handle() is
          // uvm_resource_base.  This function is not static and therefore can
          // only be used by instances of a parameterized resource.
        
          // @uvm-ieee 1800.2-2020 auto C.2.5.3.2
~009108   function uvm_resource_base get_type_handle();
~009108     return get_type();
          endfunction
          
          //----------------------------
          // Group -- NODOCS -- Read/Write Interface
          //----------------------------
          //
          // <read> and <write> provide a type-safe interface for getting and
          // setting the object in the resource container.  The interface is
          // type safe because the value argument for <write> and the return
          // value of <read> are T, the type supplied in the class parameter.
          // If either of these functions is used in an incorrect type context
          // the compiler will complain.
        
          // Function: read
          //
          //| function T read(uvm_object accessor = null);
          //
          // This function is the implementation of the uvm_resource#(T)::read 
          // method detailed in IEEE1800.2-2020 section C.2.5.4.1
          //
          // The Accellera implementation passes ~accessor~ to <do_read> and
          // returns the result.
        
          // @uvm-ieee 1800.2-2020 auto C.2.5.4.1
~000360   function T read(uvm_object accessor = null);
~000360     return do_read(accessor);
          endfunction
        
          // Function: do_read
          //
          //| virtual function T do_read(uvm_object accessor);
          //
          // The ~do_read~ method is a user-definable hook that allows users customization over
          // what actions are performed during a read operation.
          //
          // If auditing, it calls uvm_resource_debug::record_read_access before 
          // returning the value.  This detail of this API is specific to the 
          // Accellera implementation and is not being considered for contribution to 1800.2
          
          //@uvm-contrib For potential contribution to 1800.2
~000360   virtual function T do_read(uvm_object accessor);
~000360     if (uvm_resource_options::is_auditing()) begin
~000360       record_read_access(accessor);
            end
~000360     return val;
          endfunction : do_read    
          
          // Function: write
          //
          //| function void write(T t, uvm_object accessor = null);
          //
          // This function is the implementation of the uvm_resource#(T)::write 
          // method detailed in IEEE1800.2-2020 section C.2.5.4.2
          //
          // The Accellera implementation passes ~t~ and ~accessor~ to <do_write>.
        
          // @uvm-ieee 1800.2-2020 auto C.2.5.4.2
~000288   function void write(T t, uvm_object accessor = null);
~000288     do_write(t, accessor);
          endfunction
        
          // Function: do_write
          //
          //| virtual function void do_write(T t, uvm_object accessor);
          // 
          // The ~do_write~ method is a user-definable hook that allows users customization over
          // what actions are performed during a write operation.
          //
          // If auditing, it calls uvm_resource_base::record_write_access before 
          // writing the value.  This detail of this API is specific to the 
          // Accellera implementation and is not being considered for contribution to 1800.2
        
          //@uvm-contrib For potential contribution to 1800.2
~000288   virtual function void do_write(T t, uvm_object accessor);
~000288     if(is_read_only()) begin
%000000       uvm_report_error("resource", $sformatf("resource %s is read only -- cannot modify", get_name()));
%000000       return;
            end
        
            // Set the modified bit and record the transaction only if the value
            // has actually changed.
~000288     if(val == t) begin
              
%000000       return;
            end
        
        
~000288     if (uvm_resource_options::is_auditing()) begin
~000288       record_write_access(accessor);
            end
        
            // set the value and set the dirty bit
~000288     val = t;
~000288     modified = 1;
          endfunction : do_write
          
        
        
          // Function -- NODOCS -- get_highest_precedence
          //
          // In a queue of resources, locate the first one with the highest
          // precedence whose type is T.  This function is static so that it can
          // be called from anywhere.
        
~002592   static function this_type get_highest_precedence(ref uvm_resource_types::rsrc_q_t q);
        
~002592     this_type rsrc;
~002592     this_type r;
~002592     uvm_resource_types::rsrc_q_t tq;
~002592     uvm_resource_base rb;
~002592     uvm_resource_pool rp = uvm_resource_pool::get();
        
~000360     if(q.size() == 0) begin
              
%000000       return null;
            end
        
        
~002592     tq = new();
~002592     rsrc = null;
        
~002592     for(int i = 0; i < q.size(); ++i) begin
~000360       if($cast(r, q.get(i))) begin
~000360         tq.push_back(r) ;
              end
            end
        
~002592     rb = rp.get_highest_precedence(tq);
~000360     if (!$cast(rsrc, rb)) begin
               
%000000       return null;
            end
        
         
~002592     return rsrc;
        
          endfunction
        
          //@uvm-compat provided for compatibility with 1.2
%000000   function void set_priority (uvm_resource_types::priority_e pri);
%000000     uvm_resource_pool rp = uvm_resource_pool::get();
%000000     rp.set_priority(this, pri);
          endfunction
        
          //@uvm-compat provided for compatibility with 1.2
%000000   static function this_type get_by_name(string scope,
                                                string name,
                                                bit rpterr = 1);
        
%000000     uvm_resource_pool rp = uvm_resource_pool::get();
%000000     uvm_resource_base rsrc_base;
%000000     this_type rsrc;
%000000     string msg;
        
%000000     rsrc_base = rp.get_by_name(scope, name, my_type, rpterr);
%000000     if(rsrc_base == null)
%000000       return null;
        
%000000     if(!$cast(rsrc, rsrc_base)) begin
%000000       if(rpterr) begin
%000000         $sformat(msg, "Resource with name %s in scope %s has incorrect type", name, scope);
%000000         `uvm_warning("RSRCTYPE", msg);
              end
%000000       return null;
            end
        
%000000     return rsrc;
            
          endfunction
        
          //@uvm-compat provided for compatibility with 1.2
%000000   static function this_type get_by_type(string scope = "",
                                                uvm_resource_base type_handle);
        
%000000     uvm_resource_pool rp = uvm_resource_pool::get();
%000000     uvm_resource_base rsrc_base;
%000000     this_type rsrc;
%000000     string msg;
        
%000000     if(type_handle == null)
%000000       return null;
        
%000000     rsrc_base = rp.get_by_type(scope, type_handle);
%000000     if(rsrc_base == null)
%000000       return null;
        
%000000     if(!$cast(rsrc, rsrc_base)) begin
%000000       $sformat(msg, "Resource with specified type handle in scope %s was not located", scope);
%000000       `uvm_warning("RSRCNF", msg);
%000000       return null;
            end
        
%000000     return rsrc;
        
          endfunction
        
        endclass
        
        
