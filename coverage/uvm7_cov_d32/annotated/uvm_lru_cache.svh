//      // verilator_coverage annotation
        //
        //------------------------------------------------------------------------------
        // Copyright 2022 Cadence Design Systems, Inc.
        // Copyright 2022 Marvell International Ltd.
        // Copyright 2022 Mentor Graphics Corporation
        // Copyright 2021-2024 NVIDIA Corporation
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
        //------------------------------------------------------------------------------
        
        //----------------------------------------------------------------------
        // Git details (see DEVELOPMENT.md):
        //
        // $File:     src/base/uvm_lru_cache.svh $
        // $Rev:      2026-08-10 12:49:20 -0700 $
        // $Hash:     6b8f3b5a4142eb222fd01ec0f2faeb1b3f825924 $
        //
        //----------------------------------------------------------------------
        
        
        `ifndef UVM_LRU_CACHE_SVH
         `define UVM_LRU_CACHE_SVH
        
        //------------------------------------------------------------------------------
        //
        // CLASS: uvm_lru_cache(KEY_T,DATA_T)
        //
        //------------------------------------------------------------------------------
        // Implements a least recently used (LRU) cache.  
        //------------------------------------------------------------------------------
        
          // Class -- NODOCS -- uvm_lru_cache_node#(KEY_T,DATA_T)
          // Nodes within the cache store the cached value inside 
          // of a doubly linked list.
%000000   class uvm_lru_cache_node#(type KEY_T=int, type DATA_T=int);
            KEY_T key;
            DATA_T data;
        
            uvm_lru_cache_node#(KEY_T,DATA_T) prev, next;
          endclass : uvm_lru_cache_node
        
        // @uvm-contrib
        class uvm_lru_cache#(type KEY_T=int, type DATA_T=int) extends uvm_cache#(KEY_T, DATA_T);
        
          typedef uvm_lru_cache#(KEY_T,DATA_T) this_type;
        
%000000   `uvm_object_param_utils(uvm_lru_cache#(KEY_T, DATA_T))
%000000   `uvm_type_name_decl("uvm_lru_cache")
        
          // Function: new
          // Constructor, initializes the cache.
          //
          // The ~max_size~ argument defines the initial maximum size of
          // the cache.  The default ~max_size~ shall be 256.
          //
          // A ~max_size~ of 0 indicates that the cache is unsized, and will
          // not evict any keys.
          //
          extern function new(string name="unnamed-uvm_lru_cache", size_t max_size = 256);
        
          // Function: size
          // Returns the current number of elements in the cache.
          //
          extern virtual function size_t size();
        
          // Function: exists
          // Returns true if ~key~ exists in the cache, otherwise returns false.
          //
          extern virtual function bit exists(KEY_T key);
        
          // Function: get
          // Returns data associated with ~key~.
          //
          // If ~key~ exists within the cache, then the data is returned
          // via <optional_data>.
          //
          // If ~key~ does not existing within the cache, then this operation
          // shall have no effect on the cache, and shall return empty
          // <optional_data>.
          extern virtual function optional_data get(KEY_T key);
        
          // Function: put
          // Puts ~data~ in cache at index ~key~.
          //
          // If ~key~ exists within the cache, then the data associated
          // data is updated.  If ~key~ does not exists within the cache,
          // then a new data value is added at ~key~.
          //
          // If putting the key in the cache causes the number of stored
          // keys to exceed <get_max_size>, then the least recently used
          // key shall be evicted via <evict>.
          extern virtual function void put(KEY_T key, DATA_T data);
          
          // Function: evict
          // Removes the data at ~key~ from the cache.
          //
          // If ~key~ exists within the cache, then the data is returned
          // via <optional_data>.
          //
          // If ~key~ does not exist within the cache, then this operation
          // shall have no effect on the cache, and shall return empty
          // optional data.
          //
          extern virtual function optional_data evict(KEY_T key);
        
          // Function: evict_to_max
          // Implementation of uvm_cache#(KEY_T,DATA_T)::evict_to_max hook.
          //
          // Evicts least recently used keys until size is less than or
          // equal to max size.
          extern protected virtual function void evict_to_max();
        
          // Function: keys
          // Returns a queue of all keys currently in the cache.
          extern virtual function optional_keys keys();
          
          // Impementation Details
          
          typedef uvm_lru_cache_node#(KEY_T,DATA_T) node_type;
        
          // Node hash (fast lookup)
          protected node_type m_hash[KEY_T];
          
          // First node (most recently used)
          protected node_type m_begin;
          // Last node (least recently used)
          protected node_type m_end;
        
          // Function -- NODOCS --  m_update
          // Updates the node, making it the new head.
          extern virtual function void m_update(node_type node);
        
        endclass : uvm_lru_cache
        
        // uvm_lru_cache function implementations
        
%000000 function uvm_lru_cache::new(string name="unnamed-uvm_lru_cache", uvm_lru_cache::size_t max_size = 256);
%000000   super.new(name, max_size);
        endfunction : new
        
%000000 function uvm_lru_cache::size_t uvm_lru_cache::size();
%000000   return m_hash.size();
        endfunction : size
        
%000000 function bit uvm_lru_cache::exists(uvm_lru_cache::KEY_T key);
%000000   return m_hash.exists(key);
        endfunction : exists
        
%000000 function void uvm_lru_cache::m_update(uvm_lru_cache::node_type node);
          // Skip the error checking here, if node is null
          // then something is borked and it's better to cause
          // an error.
          
          // Only move if we're not already first
%000000   if (m_begin != node) 
%000000     begin
              // Removes node from the list
%000000       node.prev.next = node.next;
%000000       if (node.next != null)
%000000       begin
%000000         node.next.prev = node.prev;
              end
        
            
              // Put node before m_begin
%000000       node.next = m_begin;
%000000       m_begin.prev = node;
            
              // Makes node the head of the list
%000000       node.prev = null;
%000000       m_begin = node;
            end
        endfunction : m_update
        
%000000 function void uvm_lru_cache::evict_to_max();
%000000   size_t max_size;
%000000   max_size = get_max_size();
%000000   while (max_size && (max_size < m_hash.size()))
%000000     begin
%000000       void'(evict(m_end.key));
            end
        
        endfunction : evict_to_max  
        
%000000 function uvm_lru_cache::optional_data uvm_lru_cache::get(uvm_lru_cache::KEY_T key);
%000000   if (m_hash.exists(key)) 
%000000     begin
%000000       node_type node;
%000000       node = m_hash[key];
%000000       m_update(node);
%000000       return '{node.data};
            end
%000000   return '{};
        endfunction : get
        
%000000 function void uvm_lru_cache::put(uvm_lru_cache::KEY_T key, uvm_lru_cache::DATA_T data);
%000000   node_type node;
%000000   if (!m_hash.exists(key)) 
%000000     begin
%000000       node = new();
%000000       node.key = key;
%000000       node.data = data;
%000000       node.next = m_begin;
%000000       m_begin = node;
%000000       if (node.next == null)
%000000       begin
%000000         m_end = node;
              end
        
              else
%000000       begin
%000000         node.next.prev = node;
              end
        
%000000       m_hash[key] = node;
            end
          else 
%000000     begin
%000000       node = m_hash[key];
%000000       m_update(node);
%000000       node.data = data;
            end // else: !if(!m_hash.exists(key))
        endfunction : put
        
%000000 function uvm_lru_cache::optional_data uvm_lru_cache::evict(uvm_lru_cache::KEY_T key);
%000000   if (m_hash.exists(key)) 
%000000     begin
%000000       node_type tmp;
%000000       tmp = m_hash[key];
%000000       m_hash.delete(key);
            
              // If we're evicting the first, then
              // we have to make the next the first.
%000000       if (m_begin == tmp)
%000000       begin
%000000         m_begin = tmp.next;
              end
        
              else
%000000       begin
%000000         tmp.prev.next = tmp.next;
              end
        
            
              // Similarly, if we're evicting the last
              // then we have to make the prev the last.
%000000       if (m_end == tmp)
%000000       begin
%000000         m_end = tmp.prev;
              end
        
              else
%000000       begin
%000000         tmp.next.prev = tmp.prev;
              end
        
            
%000000       return '{tmp.data};
            end // if (m_hash.exists(key))
%000000   return '{};
        endfunction : evict
        
%000000 function uvm_lru_cache::optional_keys uvm_lru_cache::keys();
%000000   foreach(m_hash[key])
%000000     begin
%000000       keys.push_back(key);
            end
        
%000000   return keys;
        endfunction : keys
        
        
        `endif //  `ifndef UVM_LRU_CACHE_SVH
        
        
