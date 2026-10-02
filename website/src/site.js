(function(){
  var root=document.documentElement;
  function set(t){root.setAttribute('data-bs-theme',t);try{localStorage.setItem('sd-theme',t);}catch(e){}}
  document.querySelectorAll('.theme-toggle').forEach(function(b){
    b.addEventListener('click',function(){set(root.getAttribute('data-bs-theme')==='dark'?'light':'dark');});
  });
})();
